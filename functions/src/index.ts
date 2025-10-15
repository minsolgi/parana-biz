import {defineSecret} from "firebase-functions/params";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import {OpenAI} from "openai";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import axios from "axios";

admin.initializeApp();
const db = getFirestore("(default)");
const openAIKey = defineSecret("OPENAI_API_KEY");

// ✅ [추가] 카카오 토큰으로 Firebase 맞춤 토큰을 생성하는 함수
export const createFirebaseTokenWithKakao = onCall(
  { region: "asia-northeast3" },
  async (request) => {
    const kakaoAccessToken = request.data.accessToken;
    if (!kakaoAccessToken) {
      throw new HttpsError("invalid-argument", "Kakao access token is required.");
    }

    try {
      // 1. 카카오 API를 호출하여 사용자 정보를 가져옵니다.
      const response = await axios.get("https://kapi.kakao.com/v2/user/me", {
        headers: { Authorization: `Bearer ${kakaoAccessToken}` },
      });
      const kakaoUser = response.data;
      const uid = `kakao:${kakaoUser.id}`; // Firebase에서 사용할 고유 ID

      // 2. Firebase Admin SDK를 사용하여 맞춤 토큰을 생성합니다.
      const customToken = await admin.auth().createCustomToken(uid);

      return { firebaseToken: customToken };
    } catch (error) {
      logger.error("🔥 Firebase 토큰 생성 중 오류 발생:", error);
      throw new HttpsError("internal", "Failed to create Firebase custom token.");
    }
  }
);

async function generateStory(openai: OpenAI, qnaData: any): Promise<string> {
  const questionTextMap: {[key: string]: string} = {
    "start": "회고하고 싶은 시기", "ask_has_characters": "등장인물 유무",
    "ask_character_info": "등장인물 정보", "ask_background_info": "회고 당시 배경",
    "ask_meaning_yes_char": "회고록의 의미", "ask_story_yes_char": "당시 이야기",
    "ask_message_to_char": "등장인물에게 전하는 메시지", "ask_recipient_yes_char": "회고록을 전하고 싶은 사람",
    "ask_meaning_no_char": "회고록의 의미", "ask_story_no_char": "당시 이야기",
    "ask_recipient_no_char": "회고록을 전하고 싶은 사람", "ask_final_message_no_char": "회고록에 남기고 싶은 메시지",
  };
  const orderedKeys = [
    "start", "ask_has_characters", "ask_character_info", "ask_background_info",
    "ask_meaning_yes_char", "ask_story_yes_char", "ask_message_to_char",
    "ask_recipient_yes_char", "ask_meaning_no_char", "ask_story_no_char",
    "ask_recipient_no_char", "ask_final_message_no_char",
  ];
  const promptContent = orderedKeys
    .filter((key) => qnaData[key])
    .map((key) => `Q: ${questionTextMap[key] || key}\nA: ${qnaData[key]}`)
    .join("\n\n");
  const storySystemMessage = [
    "당신은 1인칭 회고록을 집필하는 작가입니다. 사용자로부터 받은 QnA를 바탕으로, 따뜻하고 서정적인 분위기의 회고 이야기를 작성해주세요.",
    "※ 아래의 작문 규칙을 지켜주세요:", "1. **글의 시점**은 반드시 ‘나’로 시작되는 **1인칭 방식**으로 유지합니다. 또한 어투도 1인칭을 사용하여 내가 쓴 회고를 느끼게 합니다.",
    "2. **글의 구조**는 다음을 따릅니다:", " - (1) 특정 시기의 회상(나이, 장소, 당시의 감정)", " - (2) 그 시절 나와 주변 인물(가족, 친구 등)의 관계 묘사", " - (3) 사건이나 일화 중심의 감정 흐름 전개", " - (4) 현재 시점에서 느끼는 생각이나 감정으로 마무리",
    "3. **문장 분위기**는 부드럽고 차분하며 감정에 집중되도록 하고, 너무 극적이거나 과장된 표현은 피합니다.", "4. 사용자 QnA 속 구체적인 표현(이름, 나이, 복장, 상황 등)은 이야기 속에 자연스럽게 녹여냅니다.",
    "5. 전체 분량은 **1000자 내외**로 구성해주세요.", "6. 스토리는 최대한 현실적으로 생성해서 읽는 사람이 어색함을 느끼지 않게 구성합니다.", "7. 별도의 제목을 작성하지 않도록 해주세요.",
  ].join("\n");
  const storyResponse = await openai.chat.completions.create({model: "gpt-4o-mini", messages: [{role: "system", content: storySystemMessage}, {role: "user", content: promptContent}]});
  const fullStory = storyResponse.choices[0].message?.content?.trim();
  if (!fullStory) throw new HttpsError("internal", "AI가 스토리를 생성하지 못했습니다.");
  return fullStory;
}

// ✅ [수정] 그림동화책 '스토리 생성' 전용 함수로 로직 전체 변경
export const generateToddlerBookSummary = onCall(
  {region: "asia-northeast3", secrets: [openAIKey]},
  async (request) => {
    // 1. storyText 대신 qnaData를 받습니다.
    const qnaData = request.data.qnaData;
    if (!qnaData) {
      throw new HttpsError("invalid-argument", "qnaData가 비어있습니다.");
    }

    try {
      const openai = new OpenAI({apiKey: openAIKey.value()});

      // 2. qnaData를 기반으로 AI에게 전달할 프롬프트를 재구성합니다.
      const promptContent = `
        - 생성 계기: ${qnaData.ask_reason || "지정 안함"}
        - 그림책 주제: ${qnaData.ask_theme || "지정 안함"}
        - 그림책 목적, 가치: ${qnaData.ask_purpose || "지정 안함"}
        - 주인공: ${qnaData.ask_characters_in_book || "지정 안함"}
        - 배경정보: ${qnaData.ask_background || "지정 안함"}
        - (역경,고난,갈등,모험) 포함 여부: ${qnaData.ask_hardship || "지정 안함"}
      `.trim();

      // 3. 시스템 메시지를 '요약'이 아닌 '스토리 생성'으로 변경합니다.
      const storySystemMessage = `
        당신은 아이들을 위한 동화 작가입니다.
        사용자가 제공한 아래의 핵심 정보들을 바탕으로, 아이들의 눈높이에 맞는 따뜻하고 교훈적인 단편 동화 스토리 초안을 작성해주세요.
        - 전체 분량은 4개의 짧은 문단으로 구성해주세요.
        - 아이들이 이해하기 쉬운 단어와 표현을 사용해주세요.
        - 긍정적이고 희망적인 분위기로 이야기를 마무리해주세요.
      `.trim();

      const storyResponse = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: [
          {role: "system", content: storySystemMessage},
          {role: "user", content: promptContent},
        ],
        // 스토리 초안이므로 길이를 넉넉하게 설정
        max_tokens: 1000,
      });

      const story = storyResponse.choices[0].message?.content?.trim();
      if (!story) {
        throw new HttpsError("internal", "AI가 스토리를 생성하지 못했습니다.");
      }

      // 4. Flutter 앱이 기대하는 'summary' 키에 생성된 스토리를 담아 반환합니다.
      return {summary: story};
    } catch (error) {
      logger.error("🔥 그림동화책 스토리 생성 중 오류 발생:", error);
      throw new HttpsError("internal", "AI 스토리 생성에 실패했습니다.");
    }
  }
);

/**
 * 주어진 동화책 스토리 전체 내용을 바탕으로 AI가 제목을 추천합니다.
 */
export const generateBookTitle = onCall(
  { region: "asia-northeast3", secrets: [openAIKey] },
  async (request) => {
    const fullStory = request.data.fullStory;
    if (!fullStory) {
      throw new HttpsError("invalid-argument", "fullStory가 비어있습니다.");
    }

    try {
      const openai = new OpenAI({ apiKey: openAIKey.value() });
      const systemMessage = `
        다음 동화책 내용 전체를 읽고, 아이들의 흥미를 끌 만한 창의적이고 따뜻한 제목을 한국어로 하나만 추천해줘.
        결과는 오직 제목 텍스트만 포함해야 하며, 따옴표나 다른 부가 설명 없이 출력해줘.
      `.trim();

      const response = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: systemMessage },
          { role: "user", content: fullStory },
        ],
        max_tokens: 60,
      });

      const title = response.choices[0].message?.content?.trim();
      if (!title) {
        throw new HttpsError("internal", "AI가 제목을 생성하지 못했습니다.");
      }

      return { title: title };
    } catch (error) {
      logger.error("🔥 AI 제목 생성 중 오류 발생:", error);
      throw new HttpsError("internal", "AI 제목 생성에 실패했습니다.");
    }
  }
);

export const processToddlerBook = onCall(
  { region: "asia-northeast3", secrets: [openAIKey], timeoutSeconds: 540 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    }
    const uid = request.auth.uid;
    const qnaData = request.data.qnaData;
    const fullStory = request.data.fullStory;

    // ✅ [수정] 데이터 유효성 검사를 fullStory 기준으로 변경합니다.
    if (!qnaData || !fullStory || !qnaData.ask_style) {
      throw new HttpsError("invalid-argument", "그림동화책 생성에 필요한 데이터(qnaData, fullStory, ask_style)가 누락되었습니다.");
    }

    try {
      const openai = new OpenAI({ apiKey: openAIKey.value() });

      // ✅ [수정] 1. 스토리를 새로 생성하는 대신, 받은 fullStory를 5개 장면으로 나눕니다.
      const splitSystemMessage = `
        당신은 주어진 동화 이야기를 4개의 주요 장면으로 나누는 편집자입니다.
        내용은 절대 수정하지 말고, 장면을 나누는 작업만 수행합니다.
        각 장면의 끝에 ':::' 구분자를 넣어주세요.
      `.trim();

      const splitResponse = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: splitSystemMessage },
          { role: "user", content: fullStory },
        ],
      });

      const splitResult = splitResponse.choices[0].message?.content?.trim();
      if (!splitResult) {
        throw new HttpsError("internal", "AI가 스토리를 분할하지 못했습니다.");
      }
      const storyPages = splitResult.split(":::").map((p) => p.trim()).filter((p) => p.length > 0);
      if (storyPages.length === 0) {
        // 분할 실패 시 전체 스토리를 첫 페이지에 넣는 등 예외 처리
        storyPages.push(fullStory);
      }

      // ✅ [수정] 이미지 프롬프트 생성 시, ask_character 대신 qnaData.ask_characters_in_book 사용
      const mainCharacter = qnaData.ask_characters_in_book || "주인공";

      // 2. 각 스토리에 맞는 이미지 생성
      const imageStyle = qnaData.ask_style || "유아용 동화책";
      const stylePrompts: {[key: string]: string} = {
        "유아용 동화책": "a cute and colorful illustration in the style of a children's book, of",
        "마블 애니메이션": "in the style of Marvel animation, a dynamic and vibrant scene of",
        "지브리 애니메이션": "in the style of Studio Ghibli animation, a whimsical and serene illustration of",
        "전래동화풍": "in the style of a traditional Korean folk tale illustration (Minhwa style), of",
        "안데르센풍": "in the style of a classic Hans Christian Andersen fairy tale, vintage and whimsical, of",
        "앤서니 브라운풍": "in the surrealist and detailed style of children's book author Anthony Browne, of",
        "이중섭풍": "in the powerful and expressive oil painting style of Korean artist Lee Jung-seob, of",
        "박수근풍": "in the unique granite-like textured style of Korean artist Park Soo-keun, of",
      };
      const selectedStyle = stylePrompts[imageStyle] || stylePrompts["유아용 동화책"];

      const generatedImageUrls = await Promise.all(storyPages.map(async (pageText, index) => {
        const imagePromptSystemMessage = `You are an AI that creates an image generation prompt. Based on the following short story scene, create a concise prompt in English. The main character is '${mainCharacter}', main character is korean. The overall style MUST be '${selectedStyle}'. The image should be simple, bright, and easy for a child to understand. Do not include quotation marks in the output.`; const imagePromptResponse = await openai.chat.completions.create({
          model: "gpt-4o-mini",
          messages: [{role: "system", content: imagePromptSystemMessage}, {role: "user", content: pageText}],
        });
        const imagePrompt = imagePromptResponse.choices[0].message?.content?.trim();
        if (!imagePrompt) throw new Error(`${index + 1}번째 이미지 프롬프트 생성 실패`);

        const imageResponse = await openai.images.generate({
          model: "gpt-image-1",
          prompt: imagePrompt,
          background: "auto",
          n: 1,
          quality: "low",
          size: "1024x1024",
          // 'response_format'을 'output_format'으로 변경
          output_format: "png",
          moderation: "auto",
        });
        const b64 = (imageResponse.data as any[])[0]?.b64_json;
        if (!b64) throw new Error(`${index + 1}번째 이미지 생성 실패`);

        const bucket = getStorage().bucket();
        const imageBuffer = Buffer.from(b64, "base64");
        const fileName = `toddler-books/${uid}/${Date.now()}_${index}.png`;
        const file = bucket.file(fileName);
        await file.save(imageBuffer, {metadata: {contentType: "image/png"}});
        await file.makePublic();
        return file.publicUrl();
      }));

      // 3. Firestore에 최종 데이터 저장 (기존과 동일)
      const bookPagesData = storyPages.map((storyText, index) => ({
        text: storyText,
        imageUrl: generatedImageUrls[index] || "",
      }));

      const toddlerBookData = {
        ownerUid: uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        title: qnaData.title || "나의 그림동화",
        type: "toddler",
        pages: bookPagesData,
        rawQnA: qnaData,
      };

      const docRef = await db.collection("toddler_books").add(toddlerBookData);

      logger.info(`✅ 그림동화책 생성 성공 (${docRef.id})`);
      return {status: "success", bookId: docRef.id};
    } catch (err: any) {
      logger.error("🔥 그림동화책 생성 중 오류 발생:", {message: err?.message, stack: err?.stack});
      throw new HttpsError("internal", "그림동화책 생성 중 오류가 발생했습니다.", err);
    }
  }
);

export const generateMemoirSummary = onCall(
  {region: "asia-northeast3", secrets: [openAIKey]},
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const qnaData = request.data.qnaData;
    if (!qnaData) throw new HttpsError("invalid-argument", "qnaData가 유효하지 않습니다.");
    try {
      const openai = new OpenAI({apiKey: openAIKey.value()});
      const fullStory = await generateStory(openai, qnaData);
      const summarySystemMessage = "다음 회고록 텍스트를 500자 내외의 자연스러운 문단으로 요약해줘.";
      const summaryResponse = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: [{role: "system", content: summarySystemMessage}, {role: "user", content: fullStory}],
      });
      const summaryText = summaryResponse.choices[0].message?.content?.trim();
      return {summary: summaryText, fullStory: fullStory};
    } catch (err: any) {
      logger.error("🔥 요약 생성 중 오류 발생:", {message: err?.message});
      throw new HttpsError("internal", "요약 생성 중 오류가 발생했습니다.", err);
    }
  }
);

export const processMemoir = onCall(
  {region: "asia-northeast3", secrets: [openAIKey], timeoutSeconds: 540},
  async (request) => {
    try {
      if (!request.auth) {
        throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
      }
      const uid = request.auth.uid;
      const qnaData = request.data.qnaData;
      const fullStory = request.data.fullStory;

      if (!qnaData || !fullStory) {
        throw new HttpsError("invalid-argument", "qnaData 또는 fullStory가 유효하지 않습니다.");
      }

      // ✅ --- 10분 쿨다운 로직 활성화 ---
      const cooldownRef = db.collection("memoirCooldowns").doc(uid);
      const cooldownDoc = await cooldownRef.get();
      if (cooldownDoc.exists) {
        const lastAttempt = cooldownDoc.data()?.lastAttemptTimestamp.toDate();
        const tenMinutesInMillis = 10 * 60 * 1000; // 10분으로 설정
        const tenMinutesAgo = new Date(Date.now() - tenMinutesInMillis);
        if (lastAttempt > tenMinutesAgo) {
          throw new HttpsError(
            "resource-exhausted",
            "10분에 한 번만 작성할 수 있습니다." // 에러 메시지 변경
          );
        }
      }

      const openai = new OpenAI({apiKey: openAIKey.value()});

      const coreContext = `
       - 주인공 정보: 필명 ${qnaData.penName || "지정 안함"}, 나이 ${qnaData.age || "지정 안함"}, gender ${qnaData.gender || "지정 안함"}
       - 회고 시기: ${qnaData.start || "알 수 없음"}
       - 주요 등장인물: ${qnaData.ask_character_info || "주인공 외 없음"}
       - 주요 배경: ${qnaData.ask_background_info || "알 수 없음"}
       `.trim();

      const splitSystemMessage = `
         당신은 주어진 이야기를 5개의 주요 장면으로 나누는 편집자입니다.
         장면을 나눌 때, 아래의 [핵심 정보]가 각 장면에 일관되게 유지되도록 내용을 구성해야 합니다.
         이는 각 장면을 바탕으로 일관된 그림을 그리기 위함입니다.
         각 장면은 ':::' 구분자로 나누어 출력해주세요.
         [핵심 정보] : ${coreContext}
       `;
      const splitResponse = await openai.chat.completions.create({model: "gpt-4o-mini", messages: [{role: "system", content: splitSystemMessage}, {role: "user", content: fullStory}]});
      const aiResult = splitResponse.choices[0].message?.content?.trim();
      if (!aiResult) throw new HttpsError("internal", "AI가 스토리를 분할하지 못했습니다.");
      let storyPages = aiResult.split(":::").map((page) => page.trim()).filter((page) => page.length > 0);
      if (storyPages.length === 0) {
        storyPages = [fullStory, "", "", "", ""];
      }

      const keywordSystemMessage = "다음 텍스트의 핵심 주제를 나타내는 키워드를 한국어로 3개 추출해줘. 쉼표(,)로 구분된 하나의 문자열로만 답해줘. 예시: \"유년 시절, 친구, 그리움\"";
      const keywordResponse = await openai.chat.completions.create({model: "gpt-4o-mini", messages: [{role: "system", content: keywordSystemMessage}, {role: "user", content: fullStory}]});
      const keywords = keywordResponse.choices[0].message?.content?.trim() ?? "키워드 없음";

      const imageStyleChoice = qnaData["ask_style_yes_char"] || qnaData["ask_style_no_char"] || "사실적";
      const stylePrompts: {[key: string]: string} = {
        "사실적": "a highly detailed, photorealistic photograph of", "스케치": "a detailed, monochrome pencil sketch of",
        "수채화": "a soft and gentle watercolor painting of", "유채화": "a classic oil painting with thick, textured brushstrokes of",
        "애니메이션풍": "in the style of modern Japanese anime, a vibrant digital illustration of", "디즈니풍": "in the style of a Disney animated feature film, a colorful and expressive digital painting of",
      };
      const selectedStylePrompt = stylePrompts[imageStyleChoice] || stylePrompts["사실적"];
      const imagePromptSystemMessage = `You are an AI that creates an image generation prompt. Based on the following text, create a prompt in English. The characters in the scene MUST be Korean. The style must be '${selectedStylePrompt}'. Do not include quotation marks in the output.`;

      const generatedImageUrls = await Promise.all(storyPages.map(async (pageText, index) => {
        const imagePromptResponse = await openai.chat.completions.create({model: "gpt-4o-mini", messages: [{role: "system", content: imagePromptSystemMessage}, {role: "user", content: pageText}]});
        const imagePrompt = imagePromptResponse.choices[0].message?.content?.trim();
        if (!imagePrompt) throw new Error(`${index + 1}번째 이미지 프롬프트 생성 실패`);
        const imageResponse = await openai.images.generate({model: "gpt-image-1", prompt: imagePrompt, background: "auto", n: 1, quality: "low", size: "1024x1024", output_format: "png", moderation: "auto"});
        const b64 = (imageResponse.data as any[])[0]?.b64_json;
        if (!b64) throw new Error(`${index + 1}번째 이미지 생성 실패`);
        const bucket = getStorage().bucket();
        const imageBuffer = Buffer.from(b64, "base64");
        const fileName = `memoir-images/${uid}/${Date.now()}_${index}.png`;
        const file = bucket.file(fileName);
        await file.save(imageBuffer, {metadata: {contentType: "image/png"}});
        await file.makePublic();
        return file.publicUrl();
      }));

      const bookPages = storyPages.map((storyText, index) => ({text: storyText, imageUrl: generatedImageUrls[index]}));
      const bookData = {ownerUid: uid, createdAt: admin.firestore.FieldValue.serverTimestamp(), title: (qnaData.penName || "나의") + " 회고록", pages: bookPages, rawQnA: qnaData, keywords: keywords};
      const docRef = await db.collection("books").add(bookData);

      // ✅ 쿨다운 시간 기록 로직 활성화
      await cooldownRef.set({lastAttemptTimestamp: admin.firestore.FieldValue.serverTimestamp()});

      logger.info(`✅ Firestore 저장 성공 (${docRef.id})`);
      return {status: "success", bookId: docRef.id};
    } catch (err: any) {
      logger.error("🔥 전체 프로세스 중 오류 발생:", {message: err?.message, stack: err?.stack});
      throw new HttpsError("internal", "회고록 생성 중 오류가 발생했습니다.", err);
    }
  },
);

// ✅ --- 쿨다운 상태 확인 함수 수정 ---
export const checkCooldownStatus = onCall(
  {region: "asia-northeast3"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    }
    const uid = request.auth.uid;
    const cooldownRef = db.collection("memoirCooldowns").doc(uid);
    const cooldownDoc = await cooldownRef.get();

    if (cooldownDoc.exists) {
      const lastAttemptTimestamp = cooldownDoc.data()?.lastAttemptTimestamp;
      if (lastAttemptTimestamp && typeof lastAttemptTimestamp.toDate === "function") {
        const lastAttempt = lastAttemptTimestamp.toDate();
        const tenMinutesInMillis = 10 * 60 * 1000; // 10분으로 설정
        const nextAvailableTime = lastAttempt.getTime() + tenMinutesInMillis;

        if (Date.now() < nextAvailableTime) {
          const remainingSeconds = Math.ceil((nextAvailableTime - Date.now()) / 1000);
          return {onCooldown: true, remainingTime: remainingSeconds};
        }
      }
    }
    return {onCooldown: false};
  }
);

/**
 * 사용자의 답변에 대한 짧은 AI 공감 응답을 생성합니다.
 * @param {onCall.Request} request - 함수 호출 요청 객체.
 * @param {string} request.data.userAnswer - 사용자의 답변 텍스트.
 * @return {Promise<{empathyText: string}>} 생성된 공감 문구가 담긴 객체.
 */
export const generateEmpathyResponse = onCall(
  {region: "asia-northeast3", secrets: [openAIKey]},
  async (request) => {
    const userAnswer = request.data.userAnswer;
    if (!userAnswer) {
      throw new HttpsError("invalid-argument", "userAnswer가 비어있습니다.");
    }
    try {
      const openai = new OpenAI({apiKey: openAIKey.value()});
      const prompt = `사용자의 다음 문장에 대해, 친구처럼 짧고 따뜻하며 자연스러운 공감의 말을 한국어로 한두 문장으로 생성해줘. 존댓말을 사용할 것: "${userAnswer}"`;
      const completion = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: [{role: "user", content: prompt}],
        max_tokens: 60,
        temperature: 0.7,
      });
      const empathyText = completion.choices[0].message.content?.trim();
      return {empathyText: empathyText};
    } catch (error) {
      logger.error("Error calling OpenAI API for empathy:", error);
      throw new HttpsError("internal", "AI 공감 응답 생성에 실패했습니다.");
    }
  }
);
/**
 * Firestore의 회고록 문서와 Storage의 관련 이미지들을 함께 삭제합니다.
 * @param {onCall.Request} request - 함수 호출 요청 객체.
 * @param {string} request.data.bookId - 삭제할 회고록 문서의 ID.
 * @return {Promise<{status: string}>} 작업 성공 상태가 담긴 객체.
 */
export const deleteBook = onCall(
  {region: "asia-northeast3"},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    }
    const uid = request.auth.uid;
    const bookId = request.data.bookId;
    if (!bookId) {
      throw new HttpsError("invalid-argument", "bookId가 필요합니다.");
    }
    const docRef = db.collection("books").doc(bookId);
    const doc = await docRef.get();
    if (!doc.exists) {
      throw new HttpsError("not-found", "삭제할 문서를 찾을 수 없습니다.");
    }
    if (doc.data()?.ownerUid !== uid) {
      throw new HttpsError("permission-denied", "문서를 삭제할 권한이 없습니다.");
    }
    try {
      const pages = doc.data()?.pages as any[];
      if (pages && pages.length > 0) {
        const bucket = getStorage().bucket();
        const deletePromises = pages
          .map((page) => {
            try {
              if (!page.imageUrl) return null;
              const url = new URL(page.imageUrl);
              const filePath = url.pathname.substring(url.pathname.indexOf("/", 1) + 1);
              return bucket.file(decodeURIComponent(filePath)).delete();
            } catch (e) {
              logger.error("이미지 URL 파싱 또는 삭제 실패", {url: page.imageUrl, error: e});
              return null;
            }
          })
          .filter((promise) => promise !== null);
        if (deletePromises.length > 0) {
          await Promise.all(deletePromises);
          logger.info(`${deletePromises.length}개의 이미지를 Storage에서 삭제했습니다.`);
        }
      }
      await docRef.delete();
      logger.info(`Firestore 문서 (${bookId})를 삭제했습니다.`);
      return {status: "success"};
    } catch (err: any) {
      logger.error("🔥 삭제 처리 중 오류 발생:", {message: err?.message, stack: err?.stack});
      throw new HttpsError("internal", "삭제 중 오류가 발생했습니다.", err);
    }
  }
);

/**
 * Firestore의 그림책 문서와 Storage의 관련 이미지들을 함께 삭제합니다.
 * @param {onCall.Request} request - 함수 호출 요청 객체.
 * @param {string} request.data.bookId - 삭제할 그림책 문서의 ID.
 * @return {Promise<{status: string}>} 작업 성공 상태가 담긴 객체.
 */
export const deleteToddlerBook = onCall(
  { region: "asia-northeast3" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    }
    const uid = request.auth.uid;
    const bookId = request.data.bookId;

    if (!bookId) {
      throw new HttpsError("invalid-argument", "bookId가 필요합니다.");
    }

    const docRef = db.collection("toddler_books").doc(bookId);
    const doc = await docRef.get();

    if (!doc.exists) {
      // 문서가 이미 없으면 성공으로 간주하고 정상 종료
      logger.info(`삭제할 문서(toddler_books/${bookId})를 찾을 수 없어 스킵합니다.`);
      return { status: "success" };
    }
    if (doc.data()?.ownerUid !== uid) {
      throw new HttpsError("permission-denied", "문서를 삭제할 권한이 없습니다.");
    }

    try {
      const pages = doc.data()?.pages as any[] | undefined; // undefined일 수 있음을 명시

      // ✅ [수정] pages 배열이 존재하고, 내용이 있을 때만 이미지 삭제 로직 실행
      if (pages && pages.length > 0) {
        const bucket = getStorage().bucket();

        const deletePromises = pages
          .map((page) => {
            // ✅ [수정] page.imageUrl이 유효한 문자열인지 먼저 확인
            if (page && typeof page.imageUrl === "string" && page.imageUrl.trim() !== "") {
              try {
                const url = new URL(page.imageUrl);
                const filePath = decodeURIComponent(url.pathname.substring(url.pathname.indexOf("/o/") + 3));
                return bucket.file(filePath).delete();
              } catch (e) {
                logger.error("잘못된 이미지 URL 파싱 또는 삭제 실패 (무시하고 계속 진행):", { url: page.imageUrl, error: e });
                return null; // 오류가 발생한 이미지는 건너뜀
              }
            }
            return null; // imageUrl이 없거나 유효하지 않으면 건너뜀
          })
          .filter((p): p is Promise<any> => p !== null);

        if (deletePromises.length > 0) {
          await Promise.all(deletePromises);
          logger.info(`${deletePromises.length}개의 그림책 이미지를 Storage에서 삭제했습니다.`);
        }
      }

      // Firestore 문서 삭제는 항상 실행
      await docRef.delete();
      logger.info(`Firestore 문서 (toddler_books/${bookId})를 삭제했습니다.`);
      return { status: "success" };
    } catch (err: any) {
      logger.error("🔥 그림책 삭제 처리 중 심각한 오류 발생:", { message: err?.message, stack: err?.stack });
      throw new HttpsError("internal", "삭제 중 오류가 발생했습니다.", err);
    }
  }
);

// ✅ [신규 추가] 인터뷰 내용을 Firestore에 저장하는 함수
export const submitInterview = onCall(
  {region: "asia-northeast3"},
  async (request) => {
    const uid = request.auth?.uid || null;
    // ✅ Flutter 앱에서 userInfo를 포함하여 데이터를 받습니다.
    const {conversation, userInfo} = request.data;

    if (!userInfo || !conversation || !Array.isArray(conversation) || conversation.length === 0) {
      throw new HttpsError("invalid-argument", "필수 데이터(userInfo, conversation)가 누락되었습니다.");
    }

    try {
      const interviewData = {
        userId: uid,
        // ✅ userInfo 객체를 그대로 저장합니다.
        userInfo: userInfo,
        conversation: conversation,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      await db.collection("interviews").add(interviewData);

      logger.info(`✅ Interview data saved. User: ${uid || "Anonymous"}, Affiliation: ${userInfo.affiliation}`);
      return {status: "success", message: "인터뷰가 성공적으로 저장되었습니다."};
    } catch (err: any) {
      logger.error("🔥 인터뷰 저장 중 오류 발생:", {message: err?.message});
      throw new HttpsError("internal", "인터뷰 저장 중 오류가 발생했습니다.", err);
    }
  }
);

// index.ts

// ✨ [최종 수정] 인터뷰 전용 공감 응답 함수 (다음 질문까지 인지)
export const generateInterviewResponse = onCall(
  {region: "asia-northeast3", secrets: [openAIKey]},
  async (request) => {
    // ✅ [수정] 다시 3가지 정보를 받습니다.
    const {previousQuestion, userAnswer, nextQuestion} = request.data;
    if (!previousQuestion || !userAnswer || !nextQuestion) {
      throw new HttpsError("invalid-argument", "필수 데이터가 누락되었습니다.");
    }
    try {
      const openai = new OpenAI({apiKey: openAIKey.value()});

      const systemMessage = `
        당신은 사용자의 답변에 공감하며 자연스럽게 다음 질문으로 대화를 이어주는 전문 인터뷰어입니다.
        주어진 [이전 질문], [사용자 답변], 그리고 다음에 이어질 [다음 질문]의 전체 문맥을 파악하여, 아래 규칙에 따라 '공감 표현'만 생성해주세요.

        1. [사용자 답변]의 핵심 내용을 짧게 짚으며 따뜻하게 공감해주세요.
        2. 당신이 생성할 '공감 표현'이, 다음에 나올 [다음 질문]으로 자연스럽게 이어주는 징검다리 역할을 해야 합니다.
        3. 당신의 역할은 '공감'까지입니다. **절대로 [다음 질문]을 직접 말해서는 안 됩니다.**
        4. 문장은 반드시 한국어 존댓말로, 1~2개의 짧은 문장으로만 구성해주세요.
        5. 문장에 "?"를 절대 사용하지 마세요.
        [예시]
        - 당신의 응답(결과물): 정말요! 민원인이 소리를 질렀다니 무척 당황스럽고 힘드셨겠습니다. 그 원인에 대해 조금 더 깊이 이야기 나눠보죠.
      `;

      const userPrompt = `
        [이전 질문]: ${previousQuestion}
        [사용자 답변]: ${userAnswer}
        [다음 질문]: ${nextQuestion}
      `;

      const completion = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: [
          {role: "system", content: systemMessage},
          {role: "user", content: userPrompt},
        ],
        max_tokens: 100,
        temperature: 0.7,
      });
      const empathyText = completion.choices[0].message.content?.trim();

      return {empathyText: empathyText};
    } catch (error) {
      logger.error("Error calling OpenAI API for interview response:", error);
      throw new HttpsError("internal", "AI 인터뷰 응답 생성에 실패했습니다.");
    }
  }
);

/**
 * '신화 만들기'의 QnA 데이터 전체를 받아 AI가 스토리 초안을 생성합니다.
 */
export const generateMythStory = onCall(
  { region: "asia-northeast3", secrets: [openAIKey] },
  async (request) => {
    const qnaData = request.data.qnaData;
    if (!qnaData) {
      throw new HttpsError("invalid-argument", "qnaData가 비어있습니다.");
    }

    try {
      const openai = new OpenAI({ apiKey: openAIKey.value() });

      // Flutter에서 받은 답변들을 AI가 이해하기 쉬운 형태로 재구성합니다.
      const promptContent = `
        - 신화 유형: ${qnaData.ask_myth_type || "지정 안함"}
        - 이야기의 핵심 구성요소: ${qnaData.ask_composition_elements || "지정 안함"}
        - 필명: ${qnaData.ask_pen_name || "지정 안함"}
        - 저자의 기본 정보: ${qnaData.ask_basic_info || "지정 안함"}
        - 이야기가 독자에게 줄 변화: ${qnaData.ask_impact || "지정 안함"}
        - 이야기가 독자에게 줄 도움: ${qnaData.ask_helpfulness || "지정 안함"}
        - 주인공과 배경: ${qnaData.ask_protagonist_background || "지정 안함"}
        - 핵심 플롯: ${qnaData.ask_plot_elements || "지정 안함"}
        - 전달하고 싶은 가치와 목표: ${qnaData.ask_values || "지정 안함"}
        - 주인공의 변화: ${qnaData.ask_transformation || "지정 안함"}
        - 마지막 장면과 여운: ${qnaData.ask_final_scene || "지정 안함"}
      `.trim();

      const systemMessage = `
        당신은 한 개인이나 기업의 서사를 '신화'의 형태로 집필하는 전문 작가입니다.
        사용자가 제공한 아래의 핵심 정보들을 바탕으로, 감동과 영감을 주는 서사적인 이야기 초안을 작성해주세요.
        - 신화의 유형과 핵심 가치를 이야기에 잘 녹여내세요.
        - 주인공의 변화 과정이 명확히 드러나도록 기승전결 구조를 갖춰주세요.
        - 전체 분량은 4개의 문단으로 구성해주세요. (나중에 4페이지 분량으로 나눌 예정)
        - 문체는 서사적이고 진중하게 작성해주세요.
      `.trim();

      const response = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: systemMessage },
          { role: "user", content: promptContent },
        ],
        max_tokens: 1500, // 충분한 길이로 생성
      });

      const fullStory = response.choices[0].message?.content?.trim();
      if (!fullStory) {
        throw new HttpsError("internal", "AI가 스토리를 생성하지 못했습니다.");
      }

      return { fullStory: fullStory };
    } catch (error) {
      logger.error("🔥 신화 스토리 생성 중 오류 발생:", error);
      throw new HttpsError("internal", "AI 스토리 생성에 실패했습니다.");
    }
  }
);

/**
 * '신화 만들기' 서비스 전용으로, 사용자의 답변에 창의적인 공감과 격려를 보냅니다.
 */
export const generateMythEmpathyResponse = onCall(
  { region: "asia-northeast3", secrets: [openAIKey] },
  async (request) => {
    // ✅ [수정] 3가지 정보를 모두 받습니다.
    const { previousQuestion, userAnswer, nextQuestion } = request.data;
    if (!previousQuestion || !userAnswer || !nextQuestion) {
      throw new HttpsError("invalid-argument", "필수 데이터(previousQuestion, userAnswer, nextQuestion)가 누락되었습니다.");
    }

    try {
      const openai = new OpenAI({ apiKey: openAIKey.value() });

      // ✅ [수정] 시스템 메시지를 '3단 구조'에 맞게 강화합니다.
      const systemMessage = `
        당신은 사용자와 '신화'를 함께 만들어가는 리스너입니다.
        주어진 [이전 질문], [사용자 답변], [다음 질문]의 전체 문맥을 파악하여,
        [사용자 답변]에 깊이 공감하면서 [다음 질문]으로 자연스럽게 대화를 이어주는 '연결 문장'을 생성해주세요.

        [규칙]
        1. 반드시 아래 '공감 어휘 목록' 중 답변의 문맥과 가장 어울리는 단어를 하나 선택하여 문장에 포함시키세요.
        2. 당신의 역할은 '연결 문장' 생성까지입니다. 절대로 [다음 질문]의 내용을 직접 언급해서는 안 됩니다.
        3. 결과는 한두 문장의 짧은 존댓말 문장이어야 합니다.

        [공감 어휘 목록]
        - 설레임, 두근두근, 놀라움, 참신함, 의미있음, 기여하게됨
      `.trim();

      // AI에게 3가지 정보를 모두 전달
      const userPrompt = `
        [이전 질문]: ${previousQuestion}
        [사용자 답변]: ${userAnswer}
        [다음 질문]: ${nextQuestion}
      `;

      const completion = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: systemMessage },
          { role: "user", content: userPrompt },
        ],
        max_tokens: 150,
        temperature: 0.7,
      });

      const empathyText = completion.choices[0].message.content?.trim();
      return { empathyText: empathyText };
    } catch (error) {
      logger.error("🔥 신화 공감 응답(3단) 생성 중 오류 발생:", error);
      throw new HttpsError("internal", "AI 공감 응답 생성에 실패했습니다.");
    }
  }
);

// index.ts (Firebase Functions)

/**
 * 주어진 동화책 스토리 전체 내용을 바탕으로 AI가 제목 4개를 추천합니다.
 */
export const generateMythTitle = onCall(
  { region: "asia-northeast3", secrets: [openAIKey] },
  async (request) => {
    const fullStory = request.data.fullStory;
    if (!fullStory) {
      throw new HttpsError("invalid-argument", "fullStory가 비어있습니다.");
    }

    try {
      const openai = new OpenAI({ apiKey: openAIKey.value() });
      const systemMessage = `
        다음 신화 이야기의 내용 전체를 읽고, 독자의 흥미를 끌 만한 창의적이고 서사적인 제목을 한국어로 정확히 4개 추천해줘.
        각 제목은 번호를 매겨서 다음 형식으로 응답해야 합니다:
        1. 첫 번째 추천 제목
        2. 두 번째 추천 제목
        3. 세 번째 추천 제목
        4. 네 번째 추천 제목
        결과에는 제목 외에 다른 설명이나 따옴표를 절대 포함하지 마세요.
      `.trim();

      const response = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: systemMessage },
          { role: "user", content: fullStory },
        ],
        max_tokens: 200,
      });

      const titlesText = response.choices[0].message?.content?.trim();
      if (!titlesText) {
        throw new HttpsError("internal", "AI가 제목을 생성하지 못했습니다.");
      }

      // AI가 생성한 텍스트("1. 제목1\n2. 제목2...")를 파싱하여 문자열 배열로 변환
      const titles = titlesText.split("\n").map((line) => {
        return line.replace(/^\d+\.\s*/, "").trim(); // "1. " 같은 앞부분 제거
      }).filter((title) => title.length > 0); // 빈 줄 제거

      // 4개의 제목을 반환
      return { titles: titles.slice(0, 4) };
    } catch (error) {
      logger.error("🔥 AI 제목 생성 중 오류 발생:", error);
      throw new HttpsError("internal", "AI 제목 생성에 실패했습니다.");
    }
  }
);

/**
 * 사용자가 제공한 키워드를 바탕으로 AI가 저자 소개를 생성합니다.
 */
export const generateAuthorIntro = onCall(
  { region: "asia-northeast3", secrets: [openAIKey] },
  async (request) => {
    const keywords = request.data.keywords;
    if (!keywords) {
      throw new HttpsError("invalid-argument", "keywords가 비어있습니다.");
    }

    try {
      const openai = new OpenAI({ apiKey: openAIKey.value() });
      const systemMessage = `
        당신은 책의 마지막 페이지에 들어갈 '저자 소개'를 작성하는 전문 편집자입니다.
        사용자가 제공한 핵심 키워드를 바탕으로, 독자에게 영감을 주는 따뜻하고 간결한 저자 소개 문구를 한국어로 생성해주세요.
        - 전체 분량은 2~3 문장으로 구성해주세요.
        - 키워드의 의미를 창의적으로 해석하여 감성적인 문장으로 만들어주세요.
      `.trim();

      const response = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: systemMessage },
          { role: "user", content: keywords },
        ],
        max_tokens: 200,
      });

      const authorIntro = response.choices[0].message?.content?.trim();
      if (!authorIntro) {
        throw new HttpsError("internal", "AI가 저자 소개를 생성하지 못했습니다.");
      }

      return { authorIntro: authorIntro };
    } catch (error) {
      logger.error("🔥 저자 소개 생성 중 오류 발생:", error);
      throw new HttpsError("internal", "AI 저자 소개 생성에 실패했습니다.");
    }
  }
);

/**
 * '신화 만들기'의 모든 데이터를 받아 최종 책을 생성하고 Firestore에 저장합니다.
 */
export const processMythBook = onCall(
  { region: "asia-northeast3", secrets: [openAIKey], timeoutSeconds: 540 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    }
    const uid = request.auth.uid;
    const qnaData = request.data.qnaData;

    if (!qnaData || !qnaData.full_story || !qnaData.title || !qnaData.ask_style) {
      throw new HttpsError("invalid-argument", "신화 생성에 필요한 데이터가 누락되었습니다.");
    }

    try {
      const openai = new OpenAI({ apiKey: openAIKey.value() });

      // 1. 받은 full_story를 4개의 장면으로 나눕니다.
      const splitSystemMessage = `
        당신은 주어진 신화 이야기를 정확히 4개의 주요 장면으로 나누는 편집자입니다.
        내용은 절대 수정하지 말고, 장면을 나누는 작업만 수행합니다.
        각 장면의 끝에 ':::' 구분자를 넣어주세요.
      `.trim();

      const splitResponse = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: splitSystemMessage },
          { role: "user", content: qnaData.full_story },
        ],
      });

      const splitResult = splitResponse.choices[0].message?.content?.trim();
      if (!splitResult) {
        throw new HttpsError("internal", "AI가 스토리를 분할하지 못했습니다.");
      }
      let storyPages = splitResult.split(":::").map((p) => p.trim()).filter((p) => p.length > 0);
      if (storyPages.length > 4) storyPages = storyPages.slice(0, 4);

      // 2. 각 장면에 맞는 이미지 생성
      const mainSubject = qnaData.ask_protagonist_background || "이야기의 주인공";
      const imageStyle = qnaData.ask_style;

      const stylePrompts: { [key: string]: string } = {
        "유아용 동화책": "a cute and colorful illustration in the style of a children's book, of",
        "마블 애니메이션": "in the style of Marvel animation, a dynamic and vibrant scene of",
        "지브리 애니메이션": "in the style of Studio Ghibli animation, a whimsical and serene illustration of",
        "전래동화풍": "in the style of a traditional Korean folk tale illustration (Minhwa style), of",
        "안데르센풍": "in the style of a classic Hans Christian Andersen fairy tale, vintage and whimsical, of",
        "앤서니 브라운풍": "in the surrealist and detailed style of children's book author Anthony Browne, of",
        "이중섭풍": "in the powerful and expressive oil painting style of Korean artist Lee Jung-seob, of",
        "박수근풍": "in the unique granite-like textured style of Korean artist Park Soo-keun, of",
        "신화풍": "in an epic, mythical, and legendary art style, of", // ✅ '신화' 기본 스타일 추가
      };
      // ✅ [수정] 기본 스타일을 '신화풍'으로 변경
      const selectedStyle = stylePrompts[imageStyle] || stylePrompts["신화풍"];

      const generatedImageUrls = await Promise.all(
        storyPages.map(async (pageText, index) => {
          const imagePromptSystemMessage = `You are an AI that creates an image generation prompt. Based on the following short story scene, create a concise prompt in English. The main subject is '${mainSubject}', and they are Korean. The overall style MUST be '${selectedStyle}'. The image should be epic and profound. Do not include quotation marks in the output.`;

          const imagePromptResponse = await openai.chat.completions.create({
            model: "gpt-4o-mini",
            messages: [{ role: "system", content: imagePromptSystemMessage }, { role: "user", content: pageText }],
          });
          const imagePrompt = imagePromptResponse.choices[0].message?.content?.trim();
          if (!imagePrompt) throw new Error(`${index + 1}번째 이미지 프롬프트 생성 실패`);
          const imageResponse = await openai.images.generate({model: "gpt-image-1", prompt: imagePrompt, background: "auto", n: 1, quality: "low", size: "1024x1024", output_format: "png", moderation: "auto"});
          const b64 = (imageResponse.data as any[])[0]?.b64_json;
          if (!b64) throw new Error(`${index + 1}번째 이미지 생성 실패`);

          const bucket = getStorage().bucket();
          const imageBuffer = Buffer.from(b64, "base64");
          // ✅ [수정] 저장 경로를 'myth-images'로 변경
          const fileName = `myth-images/${uid}/${Date.now()}_${index}.png`;
          const file = bucket.file(fileName);
          await file.save(imageBuffer, { metadata: { contentType: "image/png" } });
          await file.makePublic();
          return file.publicUrl();
        })
      );

      // 3. Firestore에 저장할 최종 데이터 조립
      const bookPagesData = storyPages.map((storyText, index) => ({
        text: storyText,
        imageUrl: generatedImageUrls[index] || "",
      }));

      const mythBookData = {
        ownerUid: uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        title: qnaData.title,
        author: qnaData.ask_author_name,
        authorIntro: qnaData.author_intro,
        finalMessage: qnaData.ask_final_message,
        pages: bookPagesData,
        rawQnA: qnaData,
      };

      // 4. 'myth_books'라는 새 컬렉션에 저장
      const docRef = await db.collection("myth_books").add(mythBookData);

      logger.info(`✅ 신화 생성 성공 (${docRef.id})`);
      return { status: "success", bookId: docRef.id };
    } catch (err: any) {
      logger.error("🔥 신화 최종 생성 중 오류 발생:", { message: err?.message, stack: err?.stack });
      throw new HttpsError("internal", "신화 생성 중 오류가 발생했습니다.", err);
    }
  }
);

export const generateSmartFarmEmpathyResponse = onCall(
  { region: "asia-northeast3", secrets: [openAIKey] },
  async (request) => {
    const { previousQuestion, userAnswer, nextQuestion } = request.data;
    if (!previousQuestion || !userAnswer || !nextQuestion) {
      throw new HttpsError("invalid-argument", "필수 데이터가 누락되었습니다.");
    }
    try {
      const openai = new OpenAI({ apiKey: openAIKey.value() });
      const systemMessage = `
        당신은 '논산시 청년 스마트팜' 인터뷰를 진행하는 전문 인터뷰어입니다.
        주어진 [이전 질문], [사용자 답변], [다음 질문]의 전체 문맥을 파악하여,
        [사용자 답변]의 핵심을 요약하며 공감하고, [다음 질문]으로 자연스럽고 흥미롭게하여 지속적인 답변이 가능하게 하는 '연결 문장'을 생성해주세요.

        [규칙]
        1. 반드시 아래 '공감 어휘 목록' 중 답변의 문맥과 가장 어울리는 단어를 하나 이상 선택하여 문장에 포함시키세요.
        2. 당신의 역할은 '연결 문장' 생성까지입니다. 절대로 [다음 질문]의 내용을 직접 언급해서는 안 됩니다.
        3. 결과는 한두 문장의 짧은 존댓말 문장이어야 합니다.

        [공감 어휘 목록]
        - 기대감, 설레임, 걱정스러움, 불확실함, 염려스러움, 그럼에도 불구하고, 용기내어, 설득하고, 어떻게 해야할지, 도움 받고 싶은, 잘 해보고 싶은, 성공하고 싶은, 자랑스러운
      `.trim();
      const userPrompt = `[이전 질문]: ${previousQuestion}\n[사용자 답변]: ${userAnswer}\n[다음 질문]: ${nextQuestion}`;

      const completion = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: systemMessage },
          { role: "user", content: userPrompt },
        ],
        max_tokens: 150,
      });
      const empathyText = completion.choices[0].message.content?.trim();
      return { empathyText: empathyText };
    } catch (error) {
      logger.error("🔥 스마트팜 공감 응답 생성 중 오류 발생:", error);
      throw new HttpsError("internal", "AI 공감 응답 생성에 실패했습니다.");
    }
  }
);

export const submitSmartFarmInterview = onCall(
  { region: "asia-northeast3" },
  async (request) => {
    const { conversation, userInfo, summary } = request.data;
    if (!userInfo || !conversation) {
      throw new HttpsError("invalid-argument", "필수 데이터가 누락되었습니다.");
    }
    try {
      const interviewData = {
        userInfo: userInfo,
        conversation: conversation,
        // ✅ [수정] summary 필드를 저장합니다. 요약이 없으면 null로 저장됩니다.
        summary: summary || null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      await db.collection("smart_farm_interviews").add(interviewData);
      return { status: "success" };
    } catch (err: any) {
      logger.error("🔥 스마트팜 인터뷰 저장 중 오류 발생:", { message: err?.message });
      throw new HttpsError("internal", "인터뷰 저장 중 오류가 발생했습니다.", err);
    }
  }
);

export const submitSmartFarmLead = onCall(
  { region: "asia-northeast3" },
  async (request) => {
    const { name, phone, email } = request.data;
    if (!name || !phone || !email) {
      throw new HttpsError("invalid-argument", "필수 데이터(이름, 전화번호, 이메일)가 누락되었습니다.");
    }
    try {
      const leadData = {
        name: name,
        phone: phone,
        email: email,
        submittedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
      // ✅ 새로운 컬렉션에 저장
      await db.collection("smart_farm_leads").add(leadData);
      return { status: "success" };
    } catch (err: any) {
      logger.error("🔥 스마트팜 리드 정보 저장 중 오류 발생:", { message: err?.message });
      throw new HttpsError("internal", "정보 저장 중 오류가 발생했습니다.", err);
    }
  }
);


// ✅ [수정] processMythBook의 이미지 생성 로직을 참조하여 재작성
export const processNewspaperArticle = onCall(
  { region: "asia-northeast3", secrets: [openAIKey], timeoutSeconds: 540 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "로그인이 필요합니다.");
    const uid = request.auth.uid;
    const { userInfo, summary, imageGenConfig } = request.data;
    if (!userInfo || !summary || !imageGenConfig) {
      throw new HttpsError("invalid-argument", "필수 데이터가 누락되었습니다.");
    }

    try {
      const openai = new OpenAI({ apiKey: openAIKey.value() });

      // 1. 최종 이미지 프롬프트 생성 (기존과 동일)
      const stylePrompts: { [key: string]: string } = {
        "정치면": "in the serious and formal illustration style of a political section newspaper cartoon",
        "경제면": "in a clean, data-driven infographic style for an economic newspaper section",
        "사회면": "in a realistic and impactful photojournalism style, capturing a key moment",
        "오피니언": "in a thoughtful and abstract style for an opinion or editorial section",
        "지역사회": "in a warm and friendly illustration style for a local community news section",
        "광고": "in a bright, eye-catching style of a full-page newspaper advertisement",
        "만화": "in the style of a classic black and white newspaper comic strip",
      };
      const selectedStyle = stylePrompts[imageGenConfig.style] || stylePrompts["사회면"];
      const hardshipPrompt = imageGenConfig.includeHardship ? "overcoming challenges and adversity," : "";

      const imagePromptSystemMessage = `Create an English image prompt for a newspaper article. The headline is "${imageGenConfig.headline}". The main character is a successful young Korean farmer. The prompt must depict a scene of ${hardshipPrompt} success and hope. The overall style MUST be: '${selectedStyle}'.`.trim();
      const imagePromptResponse = await openai.chat.completions.create({model: "gpt-4o-mini", messages: [{ role: "system", content: imagePromptSystemMessage }, { role: "user", content: summary }]});
      const finalImagePrompt = imagePromptResponse.choices[0].message?.content?.trim();
      if (!finalImagePrompt) throw new HttpsError("internal", "AI 이미지 프롬프트 생성 실패");

      logger.info(`🤖 Generated Image Prompt: ${finalImagePrompt}`);

      // 2. OpenAI Images API 직접 호출 (✅ processMythBook 로직 참조)
      const imageResponse = await openai.images.generate({
        model: "gpt-image-1", // 요청하신 모델 사용
        prompt: finalImagePrompt,
        background: "auto",
        n: 1,
        quality: "low",
        size: "1024x1024",
        output_format: "png", // b64_json을 받기 위한 설정
        moderation: "auto",
      });
      const b64 = (imageResponse.data as any[])[0]?.b64_json;
      if (!b64) throw new HttpsError("internal", "AI 이미지 데이터 생성 실패");

      // 3. Base64 이미지를 Buffer로 변환 후 Storage에 직접 저장 (✅ processMythBook 로직 참조)
      const bucket = getStorage().bucket();
      const imageBuffer = Buffer.from(b64, "base64");
      const fileName = `newspaper-articles/${uid}/${Date.now()}.png`;
      const file = bucket.file(fileName);

      await file.save(imageBuffer, { metadata: { contentType: "image/png" } });
      await file.makePublic();
      const imageUrl = file.publicUrl();

      // 4. 기사 본문 생성 (기존과 동일)
      const articleSystemMessage = `당신은 '${userInfo.penName}' 스마트팜 농부의 성공 스토리를 다루는 신문 기자입니다. [헤드라인]과 [인터뷰 요약]을 바탕으로, 독자에게 감동과 영감을 주는 긍정적인 톤의 신문 기사 본문을 3문단으로 작성해주세요.`;
      const articleResponse = await openai.chat.completions.create({model: "gpt-4o-mini", messages: [{ role: "system", content: articleSystemMessage }, { role: "user", content: `[헤드라인]: ${imageGenConfig.headline}\n\n[인터뷰 요약]:\n${summary}` }]});
      const articleBody = articleResponse.choices[0].message.content?.trim();

      // 5. Firestore에 최종 결과 저장 (기존과 동일)
      const articleData = {
        ownerUid: uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        headline: imageGenConfig.headline,
        body: articleBody,
        imageUrl: imageUrl, // 직접 생성한 URL 저장
        style: imageGenConfig.style,
        rawSummary: summary,
        imagePrompt: finalImagePrompt,
      };
      await db.collection("newspaper_articles").add(articleData);

      logger.info(`✅ 신문기사 생성 성공, user: ${uid}`);
      return { status: "success" };
    } catch (err: any) {
      logger.error("🔥 신문기사 생성 중 오류 발생:", err);
      throw new HttpsError("internal", "신문기사 생성에 실패했습니다.");
    }
  }
);

// ✅ [기능 1] 스마트팜 인터뷰 전체 내용을 요약하는 함수
export const summarizeSmartFarmInterview = onCall(
  { region: "asia-northeast3", secrets: [openAIKey] },
  async (request) => {
    const { conversation, userInfo } = request.data;
    if (!userInfo || !conversation || !Array.isArray(conversation)) {
      throw new HttpsError("invalid-argument", "필수 데이터가 누락되었습니다.");
    }

    try {
      const openai = new OpenAI({ apiKey: openAIKey.value() });
      const qaText = conversation
        .map((item: any) => `질문: ${item.question}\n답변: ${item.answer}\n\n`)
        .join("");

      const systemMessage = "당신은 '논산시 청년 스마트팜 발전 포럼'의 정책 분석가입니다. 주어진 인터뷰 Q&A 내용을 바탕으로, 핵심 내용을 간결하고 명확하게 요약하여 보고서 초안을 작성해주세요. 각 답변의 핵심 키워드와 의견이 잘 드러나도록 문단을 나누어 정리해주세요. 사용자의 의견을 객관적으로 전달하는 톤을 유지해주세요. 전체 내용은 3~4개의 문단으로 구성하고, 첫인사는 생략하고 바로 요약 내용으로 시작해주세요.".trim();
      const userPrompt = `[인터뷰 대상자 필명: ${userInfo.penName || "참여자"}]\n\n[인터뷰 전체 내용]\n${qaText}`;

      const completion = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: [{ role: "system", content: systemMessage }, { role: "user", content: userPrompt }],
      });
      const summary = completion.choices[0].message.content?.trim();
      if (!summary) throw new HttpsError("internal", "AI가 요약 생성에 실패했습니다.");
      return { summary: summary };
    } catch (error) {
      logger.error("🔥 스마트팜 인터뷰 요약 중 오류 발생:", error);
      throw new HttpsError("internal", "AI 요약 생성에 실패했습니다.");
    }
  }
);

// ✅ [기능 2] 요약본과 미래 비전을 바탕으로 신문 헤드라인 4개 추천
export const generateNewspaperHeadlines = onCall(
  { region: "asia-northeast3", secrets: [openAIKey] },
  async (request) => {
    const { summary, userInfo, futureVision } = request.data;
    if (!summary || !userInfo || !futureVision) {
      throw new HttpsError("invalid-argument", "필수 데이터(summary, userInfo, futureVision)가 누락되었습니다.");
    }
    try {
      const openai = new OpenAI({ apiKey: openAIKey.value() });
      const systemMessage = `당신은 5년 뒤 성공한 청년 스마트팜 농부 '${userInfo.penName}'에 대한 신문 기사 헤드라인을 작성하는 전문 카피라이터입니다. 주어진 [인터뷰 요약]과 사용자가 직접 서술한 [5년 뒤 미래상]을 모두 참고하여, 독자의 시선을 사로잡을 흥미롭고 긍정적인 헤드라인을 한국어로 정확히 4개 생성해주세요. 각 헤드라인은 번호를 매겨 다음 형식으로 응답해야 합니다:\n1. 첫 번째 추천 헤드라인\n2. 두 번째 추천 헤드라인\n3. 세 번째 추천 헤드라인\n4. 네 번째 추천 헤드라인`.trim();
      const userPrompt = `[인터뷰 요약]:\n${summary}\n\n[5년 뒤 미래상]:\n${futureVision}`;

      const response = await openai.chat.completions.create({
        model: "gpt-4o-mini",
        messages: [{ role: "system", content: systemMessage }, { role: "user", content: userPrompt }],
      });
      const headlinesText = response.choices[0].message?.content?.trim();
      if (!headlinesText) throw new HttpsError("internal", "AI가 헤드라인을 생성하지 못했습니다.");
      const headlines = headlinesText.split("\n").map((line) => line.replace(/^\d+\.\s*/, "").trim()).filter((line) => line.length > 0);
      return { headlines: headlines.slice(0, 4) };
    } catch (error) {
      logger.error("🔥 신문 헤드라인 생성 중 오류 발생:", error);
      throw new HttpsError("internal", "AI 헤드라인 생성에 실패했습니다.");
    }
  }
);

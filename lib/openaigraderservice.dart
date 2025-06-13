import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart'; // debugPrint를 위해
import 'package:flutter_dotenv/flutter_dotenv.dart'; // dotenv 임포트

// 채점 결과를 담을 데이터 클래스
class GradingResult {
  final bool isCorrect;
  final int score;
  final String explanation;

  GradingResult({this.isCorrect = false, this.score = 0, this.explanation = '채점 중 오류가 발생했습니다.'});

  factory GradingResult.fromJson(Map<String, dynamic> json) {
    // API 응답이 예상과 다를 경우에 대한 방어 코드
    return GradingResult(
      isCorrect: json['is_correct'] ?? false,
      score: json['score'] ?? 0,
      explanation: json['explanation'] ?? 'AI의 채점 근거를 파싱하는 데 실패했습니다.',
    );
  }
}

class OpenAiGraderService {
  // 경고: API 키를 코드에 직접 노출하는 것은 위험합니다.
  // 실제 프로덕션 환경에서는 환경 변수, Firebase Remote Config, 또는 서버를 통해 안전하게 관리해야 합니다.
  static String _apiKey = dotenv.env['OPENAI_API_KEY'] ?? 'API_KEY_NOT_FOUND';
  static const String _apiUrl = 'https://api.openai.com/v1/chat/completions';

  Future<GradingResult> gradeAnswer({
    required String question,
    required String modelAnswer, // 데이터베이스에 저장된 정답
    required String userAnswer,  // 사용자가 입력한 답
    required int fullScore,     // 문제의 만점 (fullscore 변수)
  }) async {
    //1.  API 키가 없는 경우 에러 처리
    if (_apiKey == 'API_KEY_NOT_FOUND') {
      return GradingResult(explanation: 'OpenAI API 키가 .env 파일에 설정되지 않았습니다.');
    }
    // 2. 시스템 메시지: AI에게 역할을 부여하고, 출력 형식을 강제합니다.
    final systemMessage = {
      "role": "system",
      "content": "You are a fair and precise grading assistant. Evaluate the user's answer based on the model answer and the question's intent. Your response MUST be a single, valid JSON object with three keys: 'is_correct' (boolean, true if score is greater than 0), 'score' (integer, from 0 to $fullScore), and 'explanation' (string, a brief reason for the score). Do not include any text outside of the JSON object."
    };

    // 3. 사용자 메시지: AI에게 채점할 데이터(문제, 정답, 사용자 답)를 전달합니다.
    final userMessage = {
      "role": "user",
      "content": """
      Please grade the following:
      - Question: "$question"
      - Model Answer: "$modelAnswer"
      - Maximum Score: $fullScore
      - User's Answer: "$userAnswer"
      """
    };

    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o', // 또는 'gpt-3.5-turbo' 등 사용 가능한 최신 모델
          'messages': [systemMessage, userMessage],
          'response_format': {'type': 'json_object'}, // JSON 출력 모드 활성화
        }),
      );

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(utf8.decode(response.bodyBytes));
        final messageContent = responseBody['choices'][0]['message']['content'];
        // API가 반환한 JSON 문자열을 파싱하여 GradingResult 객체로 변환
        return GradingResult.fromJson(jsonDecode(messageContent));
      } else {
        // API 에러 처리
        debugPrint('OpenAI API Error: ${response.body}');
        return GradingResult(explanation: 'API 요청 실패: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error during grading: $e');
      return GradingResult(explanation: '채점 중 예외가 발생했습니다: $e');
    }
  }
}
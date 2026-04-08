import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'package:soliplex_frontend/src/modules/quiz/quiz_session.dart';

void main() {
  group('QuizInput', () {
    group('MultipleChoiceInput', () {
      test('answerText returns selectedOption', () {
        const input = MultipleChoiceInput('Option A');
        expect(input.answerText, 'Option A');
      });

      test('isValid is always true', () {
        const input = MultipleChoiceInput('anything');
        expect(input.isValid, isTrue);
      });

      test('equality based on selectedOption', () {
        const a = MultipleChoiceInput('A');
        const b = MultipleChoiceInput('A');
        const c = MultipleChoiceInput('B');
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('TextInput', () {
      test('answerText trims whitespace', () {
        const input = TextInput('  hello  ');
        expect(input.answerText, 'hello');
      });

      test('isValid false when blank', () {
        const input = TextInput('   ');
        expect(input.isValid, isFalse);
      });

      test('isValid true when non-blank', () {
        const input = TextInput('answer');
        expect(input.isValid, isTrue);
      });

      test('equality based on raw text', () {
        const a = TextInput('hello');
        const b = TextInput('hello');
        const c = TextInput('world');
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });
  });

  group('QuestionState', () {
    test('AwaitingInput equality', () {
      const a = AwaitingInput();
      const b = AwaitingInput();
      expect(a, equals(b));
    });

    test('Composing holds input and reports canSubmit', () {
      const valid = Composing(TextInput('answer'));
      const invalid = Composing(TextInput(''));
      expect(valid.canSubmit, isTrue);
      expect(invalid.canSubmit, isFalse);
    });

    test('Submitting holds input', () {
      const state = Submitting(TextInput('answer'));
      expect(state.input.answerText, 'answer');
    });

    test('Answered holds input and result', () {
      const state = Answered(TextInput('answer'), CorrectAnswer());
      expect(state.result.isCorrect, isTrue);
    });
  });

  group('QuizSession', () {
    test('QuizNotStarted equality', () {
      const a = QuizNotStarted();
      const b = QuizNotStarted();
      expect(a, equals(b));
    });

    test('QuizInProgress exposes current question and progress', () {
      final session = QuizInProgress(
        quiz: _twoQuestionQuiz(),
        currentIndex: 0,
        results: const {},
        questionState: const AwaitingInput(),
      );
      expect(session.currentQuestion.id, 'q-1');
      expect(session.progress, 0.0);
      expect(session.isLastQuestion, isFalse);
    });

    test('QuizInProgress copyWith preserves unchanged fields', () {
      final original = QuizInProgress(
        quiz: _twoQuestionQuiz(),
        currentIndex: 0,
        results: const {},
        questionState: const AwaitingInput(),
      );
      final copy = original.copyWith(currentIndex: 1);
      expect(copy.currentIndex, 1);
      expect(copy.questionState, const AwaitingInput());
    });

    test('QuizCompleted computes score', () {
      final session = QuizCompleted(
        quiz: _twoQuestionQuiz(),
        results: const {
          'q-1': CorrectAnswer(),
          'q-2': IncorrectAnswer(expectedAnswer: 'X'),
        },
      );
      expect(session.correctCount, 1);
      expect(session.totalAnswered, 2);
      expect(session.scorePercent, 50);
    });
  });
}

Quiz _twoQuestionQuiz() => Quiz(
      id: 'quiz-1',
      title: 'Test Quiz',
      questions: const [
        QuizQuestion(id: 'q-1', text: 'Q1', type: FreeForm()),
        QuizQuestion(id: 'q-2', text: 'Q2', type: FreeForm()),
      ],
    );

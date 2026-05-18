import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import 'package:soliplex_logging/soliplex_logging.dart' show LoggerFactory;

import '../../../../soliplex_frontend.dart';
import '../../../core/routes.dart';
import '../../auth/server_entry.dart';
import '../quiz_session.dart';
import '../quiz_session_controller.dart';
import 'quiz_question.dart';
import 'quiz_results.dart';
import 'quiz_start.dart';

class QuizScreen extends StatefulWidget {
  const QuizScreen({
    super.key,
    required this.serverEntry,
    required this.roomId,
    required this.quizId,
    this.returnRoute,
  });

  final ServerEntry serverEntry;
  final String roomId;
  final String quizId;
  final String? returnRoute;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late Future<Quiz> _quizFuture;
  late final QuizSessionController _controller;
  late final Logger _logger;
  final _answerController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _logger = LogManager.instance.getLogger('quiz');
    final api = widget.serverEntry.connection.api;
    _quizFuture = _fetchQuiz();
    _controller = QuizSessionController(
      api: api,
      roomId: widget.roomId,
      logger: _logger,
    );
  }

  Future<Quiz> _fetchQuiz() async {
    try {
      return await widget.serverEntry.connection.api
          .getQuiz(widget.roomId, widget.quizId);
    } catch (error, stackTrace) {
      _logger.error(
        'Failed to load quiz ${widget.quizId} '
        'in room ${widget.roomId}',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _answerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.adaptive.arrow_back),
            tooltip: 'Back to room',
            onPressed: _handleBack,
          ),
          title: FutureBuilder<Quiz>(
            future: _quizFuture,
            builder: (_, snap) =>
                snap.hasData ? Text(snap.data!.title) : const SizedBox.shrink(),
          ),
        ),
        body: FutureBuilder<Quiz>(
          future: _quizFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              final error = snapshot.error;
              final (message, action, label) = switch (error) {
                AuthException() => (
                    'Your session has expired. Please sign in again.',
                    _handleBack,
                    'Back to Room',
                  ),
                NotFoundException() => (
                    'This quiz is no longer available.',
                    _handleBack,
                    'Back to Room',
                  ),
                NetworkException() => (
                    'Could not reach the server. Check your connection and try again.',
                    _retryFetch,
                    'Retry',
                  ),
                _ => (
                    'Something went wrong. Please try again.',
                    _retryFetch,
                    'Retry',
                  ),
              };
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(message),
                      const SizedBox(height: SoliplexSpacing.s4),
                      FilledButton(
                        onPressed: action,
                        child: Text(label),
                      ),
                    ],
                  ),
                ),
              );
            }
            return _buildContent(snapshot.data!);
          },
        ),
      ),
    );
  }

  void _retryFetch() {
    setState(() {
      _quizFuture = _fetchQuiz();
    });
  }

  Widget _buildContent(Quiz quiz) {
    final session = _controller.session.watch(context);
    final error = _controller.submissionError.watch(context);

    // State is the source of truth; the controller is a view-layer mirror for TextField.
    final providerText = switch (session) {
      QuizInProgress(questionState: Composing(input: TextInput(:final text))) =>
        text,
      QuizInProgress(
        questionState: Submitting(input: TextInput(:final text))
      ) =>
        text,
      QuizInProgress(questionState: Answered(input: TextInput(:final text))) =>
        text,
      _ => '',
    };
    if (_answerController.text != providerText) {
      _answerController.value = _answerController.value.copyWith(
        text: providerText,
        selection: TextSelection.collapsed(offset: providerText.length),
      );
    }

    return switch (session) {
      QuizNotStarted() => QuizStartView(
          quiz: quiz,
          onStart: () => _controller.start(quiz),
        ),
      QuizInProgress() => QuizQuestionView(
          session: session,
          answerController: _answerController,
          submissionError: error,
          onSelectOption: (o) =>
              _controller.updateInput(MultipleChoiceInput(o)),
          onTextChanged: (t) => _controller.updateInput(TextInput(t)),
          onSubmit: _controller.submitAnswer,
          onNext: () {
            _answerController.clear();
            _controller.nextQuestion();
          },
          onRetry: _controller.submitAnswer,
        ),
      QuizCompleted() => QuizResultsView(
          session: session,
          onBack: _handleBack,
          onRetake: () {
            _answerController.clear();
            _controller.retake();
          },
        ),
    };
  }

  Future<void> _handleBack() async {
    final session = _controller.session.value;
    if (session is QuizInProgress) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Leave Quiz?'),
          content: const Text('Your progress will be lost.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Leave'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    if (mounted) {
      final fallback = AppRoutes.room(
        widget.serverEntry.alias,
        widget.roomId,
      );
      context.go(widget.returnRoute ?? fallback);
    }
  }
}

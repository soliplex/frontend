import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

import '../../../modules/auth/server_entry.dart';
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
  });

  final ServerEntry serverEntry;
  final String roomId;
  final String quizId;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late Future<Quiz> _quizFuture;
  late final QuizSessionController _controller;
  final _answerController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final api = widget.serverEntry.connection.api;
    _quizFuture = api.getQuiz(widget.roomId, widget.quizId);
    _controller = QuizSessionController(
      api: api,
      roomId: widget.roomId,
      quizId: widget.quizId,
    );
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
              final isNotFound = error is NotFoundException;
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Failed to load quiz: $error'),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: isNotFound ? _handleBack : _retryFetch,
                        child: Text(isNotFound ? 'Back to Room' : 'Retry'),
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
      _quizFuture = widget.serverEntry.connection.api
          .getQuiz(widget.roomId, widget.quizId);
    });
  }

  Widget _buildContent(Quiz quiz) {
    final session = _controller.session.watch(context);
    final error = _controller.submissionError.watch(context);

    // Sync text controller from state (preserve cursor position)
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
    if (mounted) context.pop();
  }
}

import 'package:flutter/material.dart';

class LoadingMessageTile extends StatelessWidget {
  const LoadingMessageTile({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('Thinking...'),
        ],
      ),
    );
  }
}

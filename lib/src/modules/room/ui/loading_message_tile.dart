import 'package:flutter/material.dart';

class LoadingMessageTile extends StatelessWidget {
  const LoadingMessageTile({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Text('...'),
    );
  }
}

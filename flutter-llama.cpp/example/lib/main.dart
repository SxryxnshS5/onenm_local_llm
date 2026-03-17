// Copyright 2026 1nm. All rights reserved.
// Use of this source code is governed by a MIT license that can be
// found in the LICENSE file.

/// Example chat app demonstrating the onenm_local_llm plugin.
///
/// Shows how to:
/// - Initialise the plugin with a model and progress callback.
/// - Use `ai.chat()` for multi-turn conversation.
/// - Display messages in a Material 3 chat UI with typing indicators.
library;

import 'package:flutter/material.dart';
import 'package:onenm_local_llm/onenm_local_llm.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '1nm Local LLM Chat',
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

/// A single message in the chat UI.
class _ChatMessage {
  final String text;
  final bool isUser;
  _ChatMessage(this.text, {required this.isUser});
}

/// Full-screen chat interface that downloads a model on first launch,
/// then provides an interactive conversation with the on-device LLM.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <_ChatMessage>[];

  String _initStatus = 'Initializing...';
  bool _ready = false;
  bool _generating = false;

  late final OneNm ai = OneNm(
    model: OneNmModel.tinyllama,
    onProgress: (msg) => setState(() => _initStatus = msg),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    try {
      await ai.initialize();
      setState(() => _ready = true);
    } catch (e) {
      setState(() => _initStatus = 'Error: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _generating) return;

    _controller.clear();
    setState(() {
      _messages.add(_ChatMessage(text, isUser: true));
      _generating = true;
    });
    _scrollToBottom();

    try {
      final reply = await ai.chat(text);
      setState(() {
        _messages.add(_ChatMessage(reply.trim(), isUser: false));
        _generating = false;
      });
    } catch (e) {
      setState(() {
        _messages.add(_ChatMessage('Error: $e', isUser: false));
        _generating = false;
      });
    }
    _scrollToBottom();
  }

  @override
  void dispose() {
    ai.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('1nm Local LLM Chat')),
      body: Column(
        children: [
          // Loading indicator
          if (!_ready)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(_initStatus, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
            ),

          // Chat messages
          if (_ready)
            Expanded(
              child: _messages.isEmpty
                  ? const Center(
                      child: Text('Send a message to start chatting'))
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      itemCount: _messages.length + (_generating ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _messages.length) {
                          // Typing indicator
                          return const Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        }
                        final msg = _messages[index];
                        return _MessageBubble(msg: msg);
                      },
                    ),
            ),

          // Input bar
          if (_ready)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        enabled: !_generating,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          border: OutlineInputBorder(),
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _generating ? null : _send,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Rounded message bubble aligned left (assistant) or right (user).
class _MessageBubble extends StatelessWidget {
  final _ChatMessage msg;
  const _MessageBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: msg.isUser ? colors.primary : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: SelectableText(
          msg.text,
          style: TextStyle(
            color: msg.isUser ? colors.onPrimary : colors.onSurface,
          ),
        ),
      ),
    );
  }
}

// ignore_for_file: prefer_const_constructors, library_private_types_in_public_api, use_key_in_widget_constructors

import 'package:flutter/material.dart';
import 'package:onenm_local_llm/onenm_local_llm.dart';

class ChatbotApp extends StatefulWidget {
  @override
  _ChatbotAppState createState() => _ChatbotAppState();
}

class _ChatbotAppState extends State<ChatbotApp> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  late OneNm _ai;
  String _status = 'Initializing...';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeModel();
  }

  Future<void> _initializeModel() async {
    _ai = OneNm(
      model: OneNmModel.qwen25,
      onProgress: (status) {
        setState(() {
          _status = status;
        });
      },
    );

    try {
      await _ai.initialize();
      setState(() {
        _isLoading = false;
        _status = 'Ready to chat!';
      });
    } catch (e) {
      setState(() {
        _status = 'Error initializing model: $e';
      });
    }
  }

  Future<void> _sendMessage(String message) async {
    if (message.isEmpty || _isLoading) return;

    setState(() {
      _messages.add({'user': message});
      _controller.clear();
      _isLoading = true;
    });

    _scrollToBottom();

    try {
      final reply = await _ai.chat(message);
      setState(() {
        _messages.add({'bot': reply});
      });
    } catch (e) {
      setState(() {
        _messages.add({'bot': 'Error: $e'});
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _ai.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // KEY FIX: ensures the scaffold shrinks when keyboard appears
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text('AI Chatbot', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Status banner shown only while initializing
          if (_isLoading && _messages.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  CircularProgressIndicator(
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                  ),
                  SizedBox(height: 8.0),
                  Text(
                    _status,
                    style: TextStyle(color: Colors.greenAccent),
                  ),
                ],
              ),
            ),

          // KEY FIX: Expanded is always present so the list fills available
          // space and the input row is always pinned at the bottom
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length +
                  (_isLoading && _messages.isNotEmpty ? 1 : 0),
              itemBuilder: (context, index) {
                // Show a typing indicator as the last item while waiting
                if (index == _messages.length) {
                  return Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                        vertical: 8.0, horizontal: 16.0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.greenAccent),
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Thinking...',
                          style: TextStyle(color: Colors.greenAccent),
                        ),
                      ],
                    ),
                  );
                }

                final message = _messages[index];
                final isUser = message.containsKey('user');
                return Container(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(
                      vertical: 8.0, horizontal: 16.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 10.0, horizontal: 14.0),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.white12 : Colors.transparent,
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    child: Text(
                      message.values.first,
                      style: TextStyle(
                        color: isUser ? Colors.white : Colors.greenAccent,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Input row — always at the bottom, keyboard pushes it up naturally
          Container(
            color: Colors.black,
            padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (value) => _sendMessage(value),
                    decoration: InputDecoration(
                      hintText: 'Type your message...',
                      hintStyle: TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.white10,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send, color: Colors.greenAccent),
                  onPressed: () => _sendMessage(_controller.text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

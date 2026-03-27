import 'package:flutter/material.dart';
import 'note_summarizer_app.dart';

void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: NoteSummarizerApp(),
  ));
}
TextField(
  maxLines: 5,
  decoration: InputDecoration(
    hintText: "Enter text to summarize...",
    border: OutlineInputBorder(),
    contentPadding: EdgeInsets.all(12),
  ),
)

bool isLoading = false;
onPressed: () async {
  setState(() => isLoading = true);

  await summarizeText(); // existing function

  setState(() => isLoading = false);
}

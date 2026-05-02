import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';

final ValueNotifier<bool> isLoading = ValueNotifier<bool>(false);
final ValueNotifier<bool> isReady = ValueNotifier<bool>(false);
final ValueNotifier<double> copyProgress = ValueNotifier<double>(0.0);
final ValueNotifier<bool> isGenerating = ValueNotifier<bool>(false);
InferenceChat? _activeChat;

Future<void> stopInference() async {
  await _activeChat?.stopGeneration();
}

Future<String?> copyModel() async {
  try {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.any,
      withReadStream: true,
    );
    if (result != null && result.files.single.readStream != null) {
      final fileDetails = result.files.single;
      final stream = fileDetails.readStream!;
      final appDocDir = await getApplicationDocumentsDirectory();
      final savePath = '${appDocDir.path}/${fileDetails.name}';
      final savedFile = File(savePath);
      if (await savedFile.exists()) {
        debugPrint("Model already exists at $savePath");
        return savePath;
      }
      copyProgress.value = 0.0;
      final sink = savedFile.openWrite();

      int totalBytes = fileDetails.size;
      int bytesReceived = 0;

      await for (final chunk in stream) {
        sink.add(chunk);
        bytesReceived += chunk.length;
        if (totalBytes > 0) {
          copyProgress.value = bytesReceived / totalBytes;
          debugPrint(
            'Copying: ${(copyProgress.value * 100).toStringAsFixed(2)}% '
            '(${(bytesReceived / (1024 * 1024)).toStringAsFixed(2)} MB / '
            '${(totalBytes / (1024 * 1024)).toStringAsFixed(2)} MB)',
          );
        }
      }
      await sink.flush();
      await sink.close();
      copyProgress.value = 0.0;
      debugPrint("File successfully copied to: $savePath");
      return savePath;
    }
  } catch (e) {
    print("Error picking or saving file: $e");
  }
  return null;
}

Future<String?> pickAndInstallModel() async {
  isLoading.value = true;
  try {
    final result = await copyModel();
    debugPrint("Result is : $result");
    if (result != null) {
      await FlutterGemma.installModel(
        modelType: ModelType.gemma4,
        fileType: ModelFileType.litertlm,
      ).fromFile(result).install();
      isReady.value = true;
      return "Model installed";
    }
  } finally {
    isLoading.value = false;
  }
  return null;
}

Future<String> startChat(String text) async {
  final model = await FlutterGemma.getActiveModel(
    maxTokens: 1024,
    preferredBackend: PreferredBackend.gpu,
  );
  try {
    final chat = await model.createChat();
    _activeChat = chat;
    await chat.addQueryChunk(Message(text: text, isUser: true));
    isGenerating.value = true;
    final chunks = <String>[];
    await for (final response in chat.generateChatResponseAsync()) {
      if (response is TextResponse) {
        chunks.add(response.token);
      }
    }
    final responseText = chunks.join();
    debugPrint(
      'Response: "${responseText.length > 100 ? responseText.substring(0, 100) : responseText}"',
    );
    return responseText;
  } finally {
    isGenerating.value = false;
    _activeChat = null;
    await model.close();
  }
}

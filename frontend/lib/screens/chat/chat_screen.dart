import 'package:flutter/material.dart';
import '../../services/chat_service.dart';

class ChatMessageItem {
  final String role; // 'user' or 'assistant'
  final String text;
  final List<String> toolsCalled;
  final DateTime timestamp;
  final String status; // 'success', 'warning', 'error', 'placeholder_mode'

  ChatMessageItem({
    required this.role,
    required this.text,
    this.toolsCalled = const [],
    DateTime? timestamp,
    this.status = 'success',
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, String> toMap() {
    return {
      'role': role,
      'content': text,
    };
  }
}

class ChatScreen extends StatefulWidget {
  final int farmId;

  const ChatScreen({super.key, this.farmId = 1});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<ChatMessageItem> _messages = [];
  List<String> _suggestions = [];
  bool _isLoading = false;
  String _lastUserQuery = '';

  @override
  void initState() {
    super.initState();
    // Show welcome message immediately so user never sees a blank screen
    _addInitialAssistantMessage();
    // Fetch suggestions asynchronously in the background
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final suggestions = await ChatService.getSuggestions();
      if (mounted && suggestions.isNotEmpty) {
        setState(() {
          _suggestions = suggestions;
        });
      }
    } catch (_) {
      // Fallback suggestions are already handled inside ChatService
    }
  }

  void _addInitialAssistantMessage() {
    if (_messages.isEmpty) {
      _messages.add(
        ChatMessageItem(
          role: 'assistant',
          text:
              "👋 Welcome to your **Smart Farming AI Advisor**!\n\n"
              "How can I help you today? Ask about live soil moisture, irrigation, crops, or plant health.",
        ),
      );
    }
  }

  Future<void> _sendMessage(String userText) async {
    final query = userText.trim();
    if (query.isEmpty || _isLoading) return;

    _textController.clear();
    _lastUserQuery = query;

    // Collect conversation history BEFORE adding current query to avoid duplication
    // Exclude prior error notices so they don't pollute the prompt
    final history = _messages
        .where((m) => m.status != 'error' && (m.role == 'user' || m.role == 'assistant'))
        .map((m) => m.toMap())
        .toList();

    final userMessage = ChatMessageItem(
      role: 'user',
      text: query,
    );

    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
    });

    _scrollToBottom();

    try {
      final response = await ChatService.sendChatMessage(
        query,
        farmId: widget.farmId,
        history: history,
      );

      final reply = response['reply']?.toString() ?? 'No response received.';
      final tools = (response['tools_called'] as List<dynamic>?)
              ?.map((t) => t.toString())
              .toList() ??
          [];
      final status = response['status']?.toString() ?? 'success';

      if (mounted) {
        setState(() {
          _messages.add(
            ChatMessageItem(
              role: 'assistant',
              text: reply,
              toolsCalled: tools,
              status: status,
            ),
          );
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add(
            ChatMessageItem(
              role: 'assistant',
              text:
                  "⚠️ **Could not connect to Assistant**\n\n$e\n\n"
                  "Please ensure the backend server is running.",
              status: 'error',
            ),
          );
          _isLoading = false;
        });
      }
    }

    _scrollToBottom();
  }

  void _retryLastMessage() {
    if (_lastUserQuery.isEmpty || _isLoading) return;

    setState(() {
      // Remove trailing error message
      if (_messages.isNotEmpty && _messages.last.status == 'error') {
        _messages.removeLast();
      }
      // Remove trailing user query so it isn't rendered twice
      if (_messages.isNotEmpty &&
          _messages.last.role == 'user' &&
          _messages.last.text == _lastUserQuery) {
        _messages.removeLast();
      }
    });

    _sendMessage(_lastUserQuery);
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _clearChat() {
    setState(() {
      _messages.clear();
      _addInitialAssistantMessage();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryGreen = Color(0xFF2E7D32);
    const bgLight = Color(0xFFF7F9F3);

    return Scaffold(
      backgroundColor: bgLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        iconTheme: const IconThemeData(color: primaryGreen),
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.green.shade200),
              ),
              child: const Icon(
                Icons.smart_toy_rounded,
                color: primaryGreen,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Farm AI Assistant',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFF1E293B),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFF2E7D32),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'Online • AI Advisor',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Clear Chat',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _clearChat,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Chat Messages
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: _messages.length + (_isLoading ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index < _messages.length) {
                    return _buildMessageBubble(_messages[index]);
                  } else {
                    return _buildTypingIndicator();
                  }
                },
              ),
            ),

            // Suggestions Carousel
            if (_suggestions.isNotEmpty) _buildSuggestionsBar(),

            // Input Row
            _buildInputRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessageItem msg) {
    final isUser = msg.role == 'user';
    final isError = msg.status == 'error';
    const userBubbleColor = Color(0xFF2E7D32);
    final botBubbleColor = isError ? const Color(0xFFFFFBEB) : Colors.white;
    final botBorderColor = isError ? Colors.amber.shade300 : Colors.grey.shade200;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              margin: const EdgeInsets.only(top: 2, right: 8),
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: isError ? Colors.amber.shade100 : Colors.green.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isError ? Icons.warning_amber_rounded : Icons.smart_toy_rounded,
                size: 18,
                color: isError ? Colors.amber.shade900 : const Color(0xFF2E7D32),
              ),
            ),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? userBubbleColor : botBubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: isUser ? null : Border.all(color: botBorderColor, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tools executed badge
                  if (msg.toolsCalled.isNotEmpty) ...[
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: msg.toolsCalled.map((tool) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.green.shade200,
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle_outline_rounded,
                                size: 11,
                                color: Colors.green.shade700,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _humanizeToolName(tool),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade800,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Message text
                  _buildFormattedText(msg.text, isUser),

                  // Retry button if error
                  if (isError && _lastUserQuery.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: _isLoading ? null : () => _retryLastMessage(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.amber.shade400),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh_rounded, size: 14, color: Colors.amber.shade900),
                            const SizedBox(width: 5),
                            Text(
                              'Retry Message',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 5),

                  // Timestamp
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        _formatTime(msg.timestamp),
                        style: TextStyle(
                          fontSize: 10,
                          color: isUser
                              ? Colors.white.withValues(alpha: 0.7)
                              : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            Container(
              margin: const EdgeInsets.only(top: 2, left: 8),
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.green.shade700,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFormattedText(String content, bool isUser) {
    final textColor = isUser ? Colors.white : const Color(0xFF1E293B);
    final lines = content.split('\n');
    final List<Widget> widgets = [];

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) {
        widgets.add(const SizedBox(height: 4));
        continue;
      }

      // Check bullet
      final isBullet = line.startsWith('- ') ||
          line.startsWith('• ') ||
          line.startsWith('* ');

      final cleanLine = isBullet ? line.substring(2).trim() : rawLine;
      final spans = _parseBoldSpans(cleanLine, textColor);

      if (isBullet) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '• ',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Expanded(
                  child: RichText(
                    text: TextSpan(children: spans),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: RichText(
              text: TextSpan(children: spans),
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  List<TextSpan> _parseBoldSpans(String text, Color defaultColor) {
    final List<TextSpan> spans = [];
    final parts = text.split('**');

    for (int i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      if (i % 2 == 1) {
        // Bold
        spans.add(
          TextSpan(
            text: parts[i],
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: defaultColor,
              fontSize: 14,
            ),
          ),
        );
      } else {
        // Normal
        spans.add(
          TextSpan(
            text: parts[i],
            style: TextStyle(
              fontWeight: FontWeight.normal,
              color: defaultColor,
              fontSize: 14,
              height: 1.35,
            ),
          ),
        );
      }
    }
    return spans;
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.green.shade100,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.smart_toy_rounded,
              size: 18,
              color: Color(0xFF2E7D32),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade700),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Consulting farm data & sensors...',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionsBar() {
    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _suggestions.length,
        separatorBuilder: (_, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final prompt = _suggestions[index];
          return ActionChip(
            backgroundColor: Colors.white,
            side: BorderSide(color: Colors.green.shade300, width: 1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            avatar: Icon(
              Icons.auto_awesome,
              size: 14,
              color: Colors.green.shade700,
            ),
            label: Text(
              prompt,
              style: TextStyle(
                fontSize: 12,
                color: Colors.green.shade900,
                fontWeight: FontWeight.w500,
              ),
            ),
            onPressed: _isLoading ? null : () => _sendMessage(prompt),
          );
        },
      ),
    );
  }

  Widget _buildInputRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              enabled: !_isLoading,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Ask about soil, crops, or irrigation...',
                hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                filled: true,
                fillColor: const Color(0xFFF7F9F3),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: Colors.green.shade600, width: 1.5),
                ),
              ),
              onSubmitted: _isLoading ? null : (val) => _sendMessage(val),
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: '🎙️ Voice Assistant: Coming Soon!',
            child: Container(
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                border: Border.all(color: Colors.green.shade200, width: 1),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: Icon(Icons.mic_rounded, color: Colors.green.shade700, size: 20),
                tooltip: '🎙️ Voice Assistant: Coming Soon!',
                onPressed: () {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: const [
                          Icon(Icons.mic_none_rounded, color: Colors.white, size: 22),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '🎙️ Voice Assistant is coming soon in the next update!',
                              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: const Color(0xFF2E7D32),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            decoration: BoxDecoration(
              color: _isLoading ? Colors.grey.shade400 : const Color(0xFF2E7D32),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              onPressed:
                  _isLoading ? null : () => _sendMessage(_textController.text),
            ),
          ),
        ],
      ),
    );
  }

  String _humanizeToolName(String tool) {
    switch (tool) {
      case 'get_current_sensor_readings':
        return 'Sensors Checked';
      case 'get_farm_details':
        return 'Farm Profile';
      case 'get_irrigation_history':
        return 'Irrigation Logs';
      case 'get_disease_records':
        return 'Disease Records';
      default:
        return tool;
    }
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

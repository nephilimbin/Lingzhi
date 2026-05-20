import 'dart:convert';
import 'dart:typed_data';

// 枚举定义
enum MessageType {
  requestHello('request.hello'),
  requestAbort('request.abort'),
  requestListen('request.listen'),
  requestRead('request.read'),
  requestMute('request.mute'),
  requestConfig('request.config'),
  responseStt('response.stt'),
  responseLlmStreamResponse('response.llm_stream_response'),
  responseTts('response.tts'),
  responseTtsAudio('response.tts.audio'),
  responseConfig('response.config'),
  responseError('response.error');

  const MessageType(this.value);
  final String value;
}

enum Transport {
  websocket('websocket'),
  mqtt('mqtt');

  const Transport(this.value);
  final String value;
}

enum Modality {
  text('text'),
  audio('audio'),
  video('video'),
  picture('picture');

  const Modality(this.value);
  final String value;
}

enum AudioFormat {
  opus('opus'),
  pcm('pcm'),
  wav('wav'),
  mp3('mp3');

  const AudioFormat(this.value);
  final String value;
}

enum PlaybackState {
  start('start'),
  stop('stop'),
  end('end'),
  sentenceStart('sentence_start'),
  sentenceEnd('sentence_end');

  const PlaybackState(this.value);
  final String value;
}

enum PlaybackMode {
  manual('manual'),
  auto('auto');

  const PlaybackMode(this.value);
  final String value;
}

enum TextState {
  sentenceStart('sentence_start'),
  sentenceEnd('sentence_end');

  const TextState(this.value);
  final String value;
}

// 数据类定义
class AudioParams {
  final AudioFormat format;
  final int sampleRate;
  final int channels;
  final int frameDuration;

  const AudioParams({
    this.format = AudioFormat.opus,
    this.sampleRate = 16000,
    this.channels = 1,
    this.frameDuration = 60,
  });

  factory AudioParams.fromJson(Map<String, dynamic> json) {
    return AudioParams(
      format: AudioFormat.values.firstWhere(
        (e) => e.value == json['format'],
        orElse: () => AudioFormat.opus,
      ),
      sampleRate: json['sample_rate'] ?? 16000,
      channels: json['channels'] ?? 1,
      frameDuration: json['frame_duration'] ?? 60,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'format': format.value,
      'sample_rate': sampleRate,
      'channels': channels,
      'frame_duration': frameDuration,
    };
  }
}

class AudioPlaybackStatus {
  final PlaybackState state;
  final PlaybackMode mode;

  const AudioPlaybackStatus({
    required this.state,
    this.mode = PlaybackMode.auto,
  });

  // 静态属性 - 播放状态常量
  static const PlaybackState stateStart = PlaybackState.start;
  static const PlaybackState stateStop = PlaybackState.stop;
  static const PlaybackState stateEnd = PlaybackState.end;
  static const PlaybackState stateSentenceStart = PlaybackState.sentenceStart;
  static const PlaybackState stateSentenceEnd = PlaybackState.sentenceEnd;

  // 静态属性 - 播放模式常量
  static const PlaybackMode modeAuto = PlaybackMode.auto;
  static const PlaybackMode modeManual = PlaybackMode.manual;

  factory AudioPlaybackStatus.fromJson(Map<String, dynamic> json) {
    return AudioPlaybackStatus(
      state: PlaybackState.values.firstWhere(
        (e) => e.value == json['state'],
        orElse: () => PlaybackState.start,
      ),
      mode: PlaybackMode.values.firstWhere(
        (e) => e.value == json['mode'],
        orElse: () => PlaybackMode.auto,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {'state': state.value, 'mode': mode.value};
  }
}

class TextStatus {
  final TextState state;
  final PlaybackMode mode;
  final bool isFirstChunk;

  const TextStatus({
    required this.state,
    this.mode = PlaybackMode.auto,
    this.isFirstChunk = false,
  });

  // 静态属性 - 文本状态常量
  static const TextState stateSentenceStart = TextState.sentenceStart;
  static const TextState stateSentenceEnd = TextState.sentenceEnd;

  // 静态属性 - 播放模式常量
  static const PlaybackMode modeAuto = PlaybackMode.auto;
  static const PlaybackMode modeManual = PlaybackMode.manual;

  factory TextStatus.fromJson(Map<String, dynamic> json) {
    return TextStatus(
      state: TextState.values.firstWhere(
        (e) => e.value == json['state'],
        orElse: () => TextState.sentenceStart,
      ),
      mode: PlaybackMode.values.firstWhere(
        (e) => e.value == json['mode'],
        orElse: () => PlaybackMode.auto,
      ),
      isFirstChunk: json['is_first_chunk'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'state': state.value,
      'mode': mode.value,
      'is_first_chunk': isFirstChunk,
    };
  }
}

class SessionInfo {
  final String? sessionId;
  final List<Modality> modalities;
  final AudioParams? audioParams;
  final AudioFormat audioInputFormat;
  final AudioFormat audioOutputFormat;
  final Uint8List? audioSource;
  final AudioPlaybackStatus? audioPlaybackStatus;
  final Uint8List? videoSource;
  final String? textSource;
  final TextStatus? textStatus;
  final String? sessionRequestId;
  final String? chatMode;
  final Map<String, dynamic>? modelConfig;

  const SessionInfo({
    this.sessionId,
    this.modalities = const [],
    this.audioParams,
    this.audioInputFormat = AudioFormat.opus,
    this.audioOutputFormat = AudioFormat.opus,
    this.audioSource,
    this.audioPlaybackStatus,
    this.videoSource,
    this.textSource,
    this.textStatus,
    this.sessionRequestId,
    this.chatMode,
    this.modelConfig,
  });

  factory SessionInfo.fromJson(Map<String, dynamic> json) {
    return SessionInfo(
      sessionId: json['session_id'],
      modalities:
          (json['modalities'] as List<dynamic>?)
              ?.map(
                (e) => Modality.values.firstWhere(
                  (m) => m.value == e,
                  orElse: () => Modality.text,
                ),
              )
              .toList() ??
          [],
      audioParams:
          json['audio_params'] != null
              ? AudioParams.fromJson(json['audio_params'])
              : null,
      audioInputFormat: AudioFormat.values.firstWhere(
        (e) => e.value == json['audio_input_format'],
        orElse: () => AudioFormat.opus,
      ),
      audioOutputFormat: AudioFormat.values.firstWhere(
        (e) => e.value == json['audio_output_format'],
        orElse: () => AudioFormat.opus,
      ),
      audioSource:
          json['audio_source'] != null
              ? (json['audio_source'] is String
                  ? base64Decode(json['audio_source'])
                  : Uint8List.fromList(json['audio_source']))
              : null,
      audioPlaybackStatus:
          json['audio_playback_status'] != null
              ? AudioPlaybackStatus.fromJson(json['audio_playback_status'])
              : null,
      videoSource:
          json['video_source'] != null
              ? Uint8List.fromList(json['video_source'])
              : null,
      textSource: json['text_source'],
      textStatus:
          json['text_status'] != null
              ? TextStatus.fromJson(json['text_status'])
              : null,
      sessionRequestId: json['session_request_id'],
      chatMode: json['chat_mode'],
      modelConfig: json['model_config'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> result = {};

    if (sessionId != null) {
      result['session_id'] = sessionId;
    }
    if (modalities.isNotEmpty) {
      result['modalities'] = modalities.map((m) => m.value).toList();
    }
    if (audioParams != null) {
      result['audio_params'] = audioParams!.toJson();
    }
    result['audio_input_format'] = audioInputFormat.value;
    result['audio_output_format'] = audioOutputFormat.value;
    if (audioSource != null) {
      result['audio_source'] = audioSource!.toList();
    }
    if (audioPlaybackStatus != null) {
      result['audio_playback_status'] = audioPlaybackStatus!.toJson();
    }
    if (videoSource != null) {
      result['video_source'] = videoSource!.toList();
    }
    if (textSource != null) {
      result['text_source'] = textSource;
    }
    if (textStatus != null) {
      result['text_status'] = textStatus!.toJson();
    }
    if (sessionRequestId != null) {
      result['session_request_id'] = sessionRequestId;
    }
    if (chatMode != null) {
      result['chat_mode'] = chatMode;
    }
    if (modelConfig != null) {
      result['model_config'] = modelConfig;
    }

    return result;
  }
}

class MessageInfo {
  final MessageType type;
  final int version;
  final Transport transport;
  final SessionInfo? session;

  const MessageInfo({
    required this.type,
    this.version = 1,
    this.transport = Transport.websocket,
    this.session,
  });

  factory MessageInfo.fromJson(Map<String, dynamic> json) {
    return MessageInfo(
      type: MessageType.values.firstWhere(
        (e) => e.value == json['type'],
        orElse: () => MessageType.requestHello,
      ),
      version: json['version'] ?? 1,
      transport: Transport.values.firstWhere(
        (e) => e.value == json['transport'],
        orElse: () => Transport.websocket,
      ),
      session:
          json['session'] != null
              ? SessionInfo.fromJson(json['session'])
              : null,
    );
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> result = {
      'type': type.value,
      'version': version,
      'transport': transport.value,
    };

    if (session != null) {
      result['session'] = session!.toJson();
    }

    return result;
  }
}

// ========== 请求创建函数 ==========

/// 创建 Hello 请求
MessageInfo createHelloRequest({
  String? sessionId,
  String? sessionRequestId,
  List<Modality>? modalities,
  AudioParams? audioParams,
  AudioFormat audioInputFormat = AudioFormat.opus,
  AudioFormat audioOutputFormat = AudioFormat.opus,
  String chatMode = 'usual_mode',
}) {
  final List<Modality> finalModalities =
      modalities ?? [Modality.text, Modality.audio];
  final AudioParams finalAudioParams = audioParams ?? const AudioParams();

  final session = SessionInfo(
    sessionId: sessionId,
    sessionRequestId: sessionRequestId,
    modalities: finalModalities,
    audioParams: finalAudioParams,
    audioInputFormat: audioInputFormat,
    audioOutputFormat: audioOutputFormat,
    chatMode: chatMode,
  );

  return MessageInfo(type: MessageType.requestHello, session: session);
}

/// 创建 Abort 请求
MessageInfo createAbortRequest({
  required String sessionId,
  String? sessionRequestId,
}) {
  final session = SessionInfo(
    sessionId: sessionId,
    sessionRequestId: sessionRequestId,
  );

  return MessageInfo(type: MessageType.requestAbort, session: session);
}

/// 创建 Listen 请求
MessageInfo createListenRequest({
  required String sessionId,
  Uint8List? audioSource,
  AudioPlaybackStatus? audioPlaybackStatus,
  String? sessionRequestId,
  AudioParams? audioParams,
  AudioFormat audioInputFormat = AudioFormat.opus,
  AudioFormat audioOutputFormat = AudioFormat.opus,
}) {
  final session = SessionInfo(
    sessionId: sessionId,
    modalities: [Modality.audio],
    audioSource: audioSource,
    audioPlaybackStatus: audioPlaybackStatus,
    audioParams: audioParams ?? const AudioParams(),
    sessionRequestId: sessionRequestId,
  );

  return MessageInfo(type: MessageType.requestListen, session: session);
}

/// 创建 Read 请求
MessageInfo createReadRequest({
  required String sessionId,
  required String textSource,
  String? sessionRequestId,
  List<Modality>? additionalModalities,
}) {
  final List<Modality> finalModalities = [Modality.text];
  if (additionalModalities != null) {
    finalModalities.addAll(additionalModalities);
  }

  final session = SessionInfo(
    sessionId: sessionId,
    modalities: finalModalities,
    textSource: textSource,
    sessionRequestId: sessionRequestId,
  );

  return MessageInfo(type: MessageType.requestRead, session: session);
}

/// 创建 Mute 请求
MessageInfo createMuteRequest({
  required String sessionId,
  String? sessionRequestId,
  String chatMode = 'usual_mode',
}) {
  final session = SessionInfo(
    sessionId: sessionId,
    sessionRequestId: sessionRequestId,
    chatMode: chatMode,
  );

  return MessageInfo(type: MessageType.requestMute, session: session);
}

/// 创建 Config 请求
MessageInfo createConfigRequest({
  required String sessionId,
  required Map<String, dynamic> modelConfig,
  String? sessionRequestId,
}) {
  final session = SessionInfo(
    sessionId: sessionId,
    sessionRequestId: sessionRequestId,
    modelConfig: modelConfig,
  );

  return MessageInfo(
    type: MessageType.requestConfig,
    session: session,
  );
}

// ========== 响应解析函数 ==========

/// 解析响应消息
MessageInfo parseResponse(Map<String, dynamic> data) {
  return MessageInfo.fromJson(data);
}

/// 判断是否为STT响应
bool isSttResponse(MessageInfo message) {
  return message.type == MessageType.responseStt;
}

/// 判断是否为LLM流式响应
bool isLlmStreamResponse(MessageInfo message) {
  return message.type == MessageType.responseLlmStreamResponse;
}

/// 判断是否为TTS响应
bool isTtsResponse(MessageInfo message) {
  return message.type == MessageType.responseTts;
}

/// 判断是否为TTS音频响应
bool isTtsAudioResponse(MessageInfo message) {
  return message.type == MessageType.responseTtsAudio;
}

/// 判断是否为错误响应
bool isErrorResponse(MessageInfo message) {
  return message.type == MessageType.responseError;
}

/// 获取会话ID
String? getSessionId(MessageInfo message) {
  return message.session?.sessionId;
}

/// 获取会话请求ID
String? getSessionRequestId(MessageInfo message) {
  return message.session?.sessionRequestId;
}

/// 获取文本内容
String? getTextSource(MessageInfo message) {
  return message.session?.textSource;
}

/// 获取音频数据
Uint8List? getAudioSource(MessageInfo message) {
  return message.session?.audioSource;
}

/// 获取模态类型列表
List<Modality> getModalities(MessageInfo message) {
  return message.session?.modalities ?? [];
}

/// 获取音频播放状态
AudioPlaybackStatus? getAudioPlaybackStatus(MessageInfo message) {
  return message.session?.audioPlaybackStatus;
}

/// 获取文本状态
TextStatus? getTextStatus(MessageInfo message) {
  return message.session?.textStatus;
}

/// 判断是否为第一个文本块
bool isFirstChunk(MessageInfo message) {
  return message.session?.textStatus?.isFirstChunk ?? false;
}

// 便捷函数
MessageInfo createRequestMessage(
  MessageType type,
  Map<String, dynamic> params,
) {
  switch (type) {
    case MessageType.requestHello:
      return createHelloRequest(
        sessionId: params['sessionId'],
        modalities: params['modalities'],
        audioParams: params['audioParams'],
        audioInputFormat: params['audioInputFormat'] ?? AudioFormat.opus,
        audioOutputFormat: params['audioOutputFormat'] ?? AudioFormat.opus,
      );
    case MessageType.requestAbort:
      return createAbortRequest(
        sessionId: params['sessionId'],
        sessionRequestId: params['sessionRequestId'],
      );
    case MessageType.requestListen:
      return createListenRequest(
        sessionId: params['sessionId'],
        audioSource: params['audioSource'],
        audioPlaybackStatus: params['audioPlaybackStatus'],
        sessionRequestId: params['sessionRequestId'],
      );
    case MessageType.requestRead:
      return createReadRequest(
        sessionId: params['sessionId'],
        textSource: params['textSource'],
        sessionRequestId: params['sessionRequestId'],
        additionalModalities: params['additionalModalities'],
      );
    default:
      throw ArgumentError('Unknown request type: $type');
  }
}

MessageInfo parseResponseMessage(Map<String, dynamic> data) {
  /// 解析响应消息的便捷函数
  return parseResponse(data);
}

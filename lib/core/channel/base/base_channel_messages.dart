part of 'base_channel.dart';

/// Set of functionality related to message
extension Messages on BaseChannel {
  /// Sends [UserMessage] on this channel with [text].
  ///
  /// It returns [UserMessage] with [MessageSendingStatus.pending] and
  /// [onCompleted] will be invoked once the message has been sent completely.
  /// Channel event [ChannelEventHandler.onMessageReceived] will be invoked
  /// on all other members' end.
  /// NOTE that the pending message does not have a messageId.
  UserMessage sendUserMessageWithText(
    String text, {
    OnUserMessageCallback? onCompleted,
  }) {
    final params = UserMessageParams(message: text);
    return sendUserMessage(
      params,
      onCompleted: onCompleted,
    );
  }

  /// Sends [UserMessage] on this channel with [params].
  ///
  /// It returns [UserMessage] with [MessageSendingStatus.pending] and
  /// [onCompleted] will be invoked once the message has been sent completely.
  /// Channel event [ChannelEventHandler.onMessageReceived] will be invoked
  /// on all other members' end.
  /// NOTE that the pending message does not have a messageId.
  UserMessage sendUserMessage(
    UserMessageParams params, {
    OnUserMessageCallback? onCompleted,
  }) {
    if (params.message.isEmpty) {
      throw InvalidParameterError();
    }

    // final req = ChannelUserMessageSendRequest(
    //   channelType: channelType,
    //   channelUrl: channelUrl,
    //   params: params,
    // );

    // final pending = req.pending;

    // if (!_sdk.state.hasActiveUser) {
    //   final error = ConnectionRequiredError();
    //   pending
    //     ..errorCode = error.code
    //     ..sendingStatus = MessageSendingStatus.failed;
    //   if (onCompleted != null) onCompleted(pending, error);
    //   return pending;
    // }

    // pending.sendingStatus = MessageSendingStatus.pending;
    // pending.sender = Sender.fromUser(_sdk.state.currentUser, this);

    // _sdk.cmdManager.send(req).then((result) {
    //   if (result == null) return;
    //   final msg = BaseMessage.msgFromJson<UserMessage>(
    //     result.payload,
    //     type: result.cmd,
    //   );
    //   if (onCompleted != null && msg != null) onCompleted(msg, null);
    // }).catchError((e) {
    //   // pending.errorCode = e?.code ?? ErrorCode.unknownError;
    //   pending
    //     ..errorCode = e.code
    //     ..sendingStatus = MessageSendingStatus.failed;
    //   if (onCompleted != null) onCompleted(pending, e);
    // });

    if (params.mentionedUserIds != null) {
      if (params.mentionedUserIds!.isNotEmpty && params.isChannelMention == false) {
        params.mentionType = MentionType.users;
      }
    }

    final cmd = Command.buildUserMessage(
      channelUrl,
      params,
      Uuid().v1(),
    );

    final pending = BaseMessage.msgFromJson<UserMessage>(
      cmd.payload,
      channelType: channelType,
      type: cmd.cmd,
    )!;

    //return mentionedUsers if params include mentionedUsers
    pending.mentionedUsers = params.mentionedUsers ?? [];

    if (!_sdk.state.hasActiveUser) {
      final error = ConnectionRequiredError();
      pending
        ..errorCode = error.code
        ..sendingStatus = MessageSendingStatus.failed;
      if (onCompleted != null) onCompleted(pending, error);
      return pending;
    }

    pending.sendingStatus = MessageSendingStatus.pending;
    pending.sender = Sender.fromUser(_sdk.state.currentUser, this);

    _sdk.cmdManager.sendCommand(cmd).then((result) {
      if (result == null) return;
      result.payload['mentioned_users'] = params.mentionedUsers?.map((e) => e.toJson()).toList();
      final msg = BaseMessage.msgFromJson<UserMessage>(
        result.payload,
        type: result.cmd,
      );
      if (onCompleted != null && msg != null) onCompleted(msg, null);
    }).catchError((e) {
      pending
        ..errorCode = e?.code ?? ErrorCode.unknownError
        ..sendingStatus = MessageSendingStatus.failed;
      if (onCompleted != null) onCompleted(pending, e);
    });

    return pending;
  }

  /// Resends failed [UserMessage] on this channel with [message].
  ///
  /// It returns [UserMessage] with [MessageSendingStatus.pending] and
  /// [onCompleted] will be invoked once the message has been sent completely.
  /// Channel event [ChannelEventHandler.onMessageReceived] will be invoked
  /// on all other members' end.
  /// NOTE that the pending message does not have a messageId.
  UserMessage resendUserMessage(
    UserMessage message, {
    OnUserMessageCallback? onCompleted,
  }) {
    if (message.sendingStatus != MessageSendingStatus.failed) {
      throw InvalidParameterError();
    }
    if (message.channelUrl != channelUrl) {
      throw InvalidParameterError();
    }
    if (!message.isResendable()) {
      throw InvalidParameterError();
    }

    final params = UserMessageParams.withMessage(message, deepCopy: false);
    return sendUserMessage(
      params,
      onCompleted: onCompleted,
    );
  }

  /// Updates [UserMessage] on this channel with [messageId] and [params].
  Future<UserMessage> updateUserMessage(int messageId, UserMessageParams params) async {
    if (messageId <= 0) {
      throw InvalidParameterError();
    }

    final cmd = Command.buildUpdateUserMessage(
      channelUrl,
      messageId,
      params,
    );

    try {
      final res = await _sdk.cmdManager.sendCommand(cmd);
      if (res != null) {
        return BaseMessage.msgFromJson<UserMessage>(
          res.payload,
          type: cmd.cmd,
        )!; //mark!
      } else {
        logger.e('failed to update user message');
        throw WebSocketError();
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Sends [FileMessage] on this channel with [params].
  ///
  /// It returns [FileMessage] with [MessageSendingStatus.pending] and
  /// [onCompleted] will be invoked once the message has been sent completely.
  /// Channel event [ChannelEventHandler.onMessageReceived] will be invoked
  /// on all other members' end.
  /// NOTE that the pending message does not have a messageId.
  FileMessage sendFileMessage(
    FileMessageParams params, {
    OnFileMessageCallback? onCompleted,
    OnUploadProgressCallback? progress,
  }) {
    if (!params.uploadFile.hasSource) {
      throw InvalidParameterError();
    }

    UploadResponse? upload;
    int? fileSize;
    String? url;

    final pending = FileMessage.fromParams(params: params, channel: this);
    pending.sendingStatus = MessageSendingStatus.pending;
    pending.sender = Sender.fromUser(_sdk.state.currentUser, this);

    final queue = _sdk.getMsgQueue(channelUrl);
    final task = AsyncSimpleTask(
      () async {
        if (params.uploadFile.hasBinary) {
          try {
            upload = await _sdk.api
                .send<UploadResponse>(
                    ChannelFileUploadRequest(channelUrl: channelUrl, requestId: pending.requestId!, params: params, onProgress: progress))
                .timeout(
              Duration(seconds: _sdk.options.fileTransferTimeout),
              onTimeout: () {
                logger.e('upload timeout');
                if (onCompleted != null) {
                  onCompleted(
                    pending..sendingStatus = MessageSendingStatus.failed,
                    SBError(
                      message: 'upload timeout',
                      code: ErrorCode.fileUploadTimeout,
                    ),
                  );
                }
                //
                throw SBError(code: ErrorCode.fileUploadTimeout);
              },
            );
            if (upload == null) {
              throw SBError(code: ErrorCode.fileUploadTimeout);
            }
            fileSize = upload?.fileSize;
            url = upload?.url;
          } catch (e) {
            rethrow;
          }
        }

        if (fileSize != null) params.uploadFile.fileSize = fileSize;
        if (url != null) params.uploadFile.url = url;

        final cmd = Command.buildFileMessage(
          channelUrl: channelUrl,
          params: params,
          requestId: pending.requestId,
          requireAuth: upload?.requireAuth,
          thumbnails: upload?.thumbnails,
        );

        final msgFromPayload = BaseMessage.msgFromJson<FileMessage>(
          cmd.payload,
          channelType: channelType,
          type: cmd.cmd,
        )!;

        if (!_sdk.state.hasActiveUser) {
          final error = ConnectionRequiredError();
          msgFromPayload
            ..errorCode = error.code
            ..sendingStatus = MessageSendingStatus.failed;
          if (onCompleted != null) onCompleted(msgFromPayload, error);
          return msgFromPayload;
        }
        if (_sdk.webSocket == null || _sdk.webSocket?.isConnected() == false) {
          final request = ChannelFileMessageSendApiRequest(
            channelType: channelType,
            channelUrl: channelUrl,
            params: params,
            thumbnails: upload?.thumbnails,
            requireAuth: upload?.requireAuth,
          );
          final msg = await _sdk.api.send<FileMessage>(request);
          if (onCompleted != null) onCompleted(msg, null);
        } else {
          _sdk.cmdManager.sendCommand(cmd).then((result) {
            if (result == null) return;
            result.payload['mentioned_users'] = params.mentionedUsers?.map((e) => e.toJson()).toList();
            final msg = BaseMessage.msgFromJson<FileMessage>(
              result.payload,
              type: result.cmd,
            );
            if (onCompleted != null && msg != null) onCompleted(msg, null);
          }).catchError((e) {
            pending
              ..errorCode = e?.code ?? ErrorCode.unknownError
              ..sendingStatus = MessageSendingStatus.failed;
            if (onCompleted != null) onCompleted(pending, e);
          });
        }
      },
      onCancel: () {
        if (onCompleted != null) onCompleted(pending, OperationCancelError());
      },
    );

    queue.enqueue(task);

    _sdk.setUploadTask(pending.requestId!, task);
    _sdk.setMsgQueue(channelUrl, queue);

    return pending;
  }

  bool cancelUploadingFileMessage(String requestId) {
    if (requestId.isEmpty) {
      throw InvalidParameterError();
    }
    final task = _sdk.getUploadTask(requestId);
    if (task == null) {
      throw NotFoundError();
    }

    final queue = _sdk.getMsgQueue(channelUrl);
    _sdk.api.cancelUploadingFile(requestId);
    return queue.cancel(task.hashCode);
  }

  /// Resends failed [FileMessage] on this channel with [message].
  ///
  /// It returns [FileMessage] with [MessageSendingStatus.pending] and
  /// [onCompleted] will be invoked once the message has been sent completely.
  /// Channel event [ChannelEventHandler.onMessageReceived] will be invoked
  /// on all other members' end.
  /// NOTE that the pending message does not have a messageId.
  FileMessage resendFileMessage(
    FileMessage message, {
    required FileMessageParams params,
    OnFileMessageCallback? onCompleted,
    OnUploadProgressCallback? progress,
  }) {
    if (message.sendingStatus != MessageSendingStatus.failed) {
      throw InvalidParameterError();
    }
    if (message.channelUrl != channelUrl) {
      throw InvalidParameterError();
    }
    if (!message.isResendable()) {
      throw InvalidParameterError();
    }

    return sendFileMessage(
      params,
      progress: progress,
      onCompleted: onCompleted,
    );
  }

  /// Updates [FileMessage] on this channel with [messageId] and [params].
  Future<FileMessage> updateFileMessage(int messageId, FileMessageParams params) async {
    if (messageId <= 0) {
      throw InvalidParameterError();
    }

    final cmd = Command.buildUpdateFileMessage(
      channelUrl,
      messageId,
      params,
    );

    try {
      final res = await _sdk.cmdManager.sendCommand(cmd);
      if (res != null) {
        return BaseMessage.msgFromJson<FileMessage>(
          res.payload,
          type: cmd.cmd,
        )!; //mark!
      } else {
        logger.e('failed to update file message');
        throw WebSocketError();
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Deletes message with given [messageId].
  ///
  /// After this method completes successfully, channel event
  /// [ChannelEventHandler.onMessageDeleted] will be invoked.
  Future<void> deleteMessage(int messageId) async {
    if (messageId <= 0) {
      throw InvalidParameterError();
    }

    await _sdk.api.send(ChannelMessageDeleteRequest(
      channelType: channelType,
      channelUrl: channelUrl,
      messageId: messageId,
    ));
  }

  /// Translates a [message] with given list of [targetLanguages].
  ///
  /// An element of target language should be from
  /// http://www.lingoes.net/en/translator/langcode.htm
  Future<UserMessage> translateUserMessage(
    UserMessage message,
    List<String> targetLanguages,
  ) async {
    if (message.messageId <= 0) {
      throw InvalidParameterError();
    }
    if (targetLanguages.isEmpty) {
      throw InvalidParameterError();
    }

    return _sdk.api.send<UserMessage>(
      ChannelMessageTranslateRequest(
        channelType: channelType,
        channelUrl: channelUrl,
        messageId: message.messageId,
        targetLanguages: targetLanguages,
      ),
    );
  }

  /// Copies [message] to [targetChannel].
  ///
  /// It returns either [UserMessage] or [FileMessage] with
  /// [MessageSendingStatus.pending] and [onCompleted] will be invoked once the
  /// message has been sent completely. Channel event
  /// [ChannelEventHandler.onMessageReceived] will be invoked on all
  /// other members' end.
  BaseMessage copyMessage(
    BaseMessage message,
    BaseChannel targetChannel, {
    OnMessageCallback? onCompleted,
  }) {
    if (message.channelUrl != channelUrl) {
      throw InvalidParameterError();
    }

    // Do not copy [extendedMessage] in message
    message.extendedMessage.clear();

    if (message is UserMessage) {
      final params = UserMessageParams.withMessage(message, deepCopy: false);
      if (params.pollId != null)
        throw SBError(
          message: 'Message with Poll can not be copied',
          code: ErrorCode.notSupportedError,
        );
      return targetChannel.sendUserMessage(
        params,
        onCompleted: onCompleted,
      );
    } else if (message is FileMessage) {
      final params = FileMessageParams.withMessage(message, deepCopy: false);
      return targetChannel.sendFileMessage(
        params,
        onCompleted: onCompleted,
      );
    } else {
      throw InvalidParameterError();
    }
  }

  /// Retrieves a list of [BaseMessage] with given [timestamp] and [params].
  Future<List<BaseMessage>> getMessagesByTimestamp(
    int timestamp,
    MessageListParams params,
  ) async {
    if (timestamp <= 0) {
      throw InvalidParameterError();
    }

    if (channelType == ChannelType.group) {
      params.showSubChannelMessagesOnly = false;
    }

    return _sdk.api.send<List<BaseMessage>>(
      ChannelMessagesGetRequest(
        channelType: channelType,
        channelUrl: channelUrl,
        params: params.toJson(),
        timestamp: timestamp,
      ),
    );
  }

  /// Retrieves a list of [BaseMessage] with given [messageId] and [params].
  Future<List<BaseMessage>> getMessagesById(
    int messageId,
    MessageListParams params,
  ) async {
    if (messageId <= 0) {
      throw InvalidParameterError();
    }

    if (channelType == ChannelType.group) {
      params.showSubChannelMessagesOnly = false;
    }

    return _sdk.api.send<List<BaseMessage>>(
      ChannelMessagesGetRequest(
        channelType: channelType,
        channelUrl: channelUrl,
        params: params.toJson(),
        messageId: messageId,
      ),
    );
  }

  /// Retreieve massage change logs with [timestamp] or [token] and [params].
  Future<MessageChangeLogsResponse> getMessageChangeLogs({
    int? timestamp,
    String? token,
    required MessageChangeLogParams params,
  }) async {
    return _sdk.api.send(
      ChannelMessageChangeLogGetRequest(
        channelType: channelType,
        channelUrl: channelUrl,
        params: params,
        token: token,
        timestamp: timestamp ?? ExtendedInteger.max,
      ),
    );
  }

  /// Cancels scheduled message
  Future<void> cancelScheduledMessage(
    int scheduledMessageId, {
    OnScheduledMessageCancelCallback? callback,
  }) async {
    try {
      return _sdk.api.send(
        GroupChannelScheduledMessageCancelRequest(
          channelUrl: channelUrl,
          scheduledMessageId: scheduledMessageId,
        ),
      );
    } catch (e) {
      if (callback != null) {
        final error = SBError(message: 'Failed Sending Request');
        callback(error);
      }
    }
  }

  /// Update scheduled user message
  Future<ScheduledUserMessage> updateScheduledUserMessage({
    required ScheduledUserMessageUpdateParams params,
    required int scheduledMessageid,
    OnScheduledMessageCallback<ScheduledUserMessage>? callback,
  }) async {
    try {
      final result = await _sdk.api.send(
        GroupChannelScheduledUserMessageUpdateRequest(
          scheduledMessageId: scheduledMessageid,
          channelUrl: channelUrl,
          params: params,
        ),
      );
      if (callback != null) {
        callback(result, null);
      }
      return result;
    } catch (e) {
      if (callback != null) {
        final error = SBError(message: 'Failed Sending Request');
        callback(null, error);
      }
      rethrow;
    }
  }

  /// Update scheduled file message
  Future<ScheduledFileMessage> updateScheduledFileMessage({
    required ScheduledFileMessageUpdateParams params,
    required int scheduledMessageid,
    OnScheduledMessageCallback<ScheduledFileMessage>? callback,
  }) async {
    try {
      final result = await _sdk.api.send(
        GroupChannelScheduledFileMessageUpdateRequest(
          scheduledMessageId: scheduledMessageid,
          channelUrl: channelUrl,
          params: params,
        ),
      );

      if (callback != null) {
        callback(result, null);
      }

      return result;
    } catch (e) {
      if (callback != null) {
        final error = SBError(message: 'Failed Sending Request');
        callback(null, error);
      }
      rethrow;
    }
  }

  /// Creates scheduled user message
  Future<ScheduledUserMessage> createScheduledUserMessage(
    ScheduledUserMessageParams userMessageParams, {
    OnScheduledMessageCallback<ScheduledUserMessage>? callback,
  }) async {
    try {
      final result = await _sdk.api.send(
        GroupChannelScheduledUserMessageSendRequest(
          channelUrl: channelUrl,
          params: userMessageParams,
        ),
      );
      if (callback != null) {
        callback(result, null);
      }
      return result;
    } catch (e) {
      if (callback != null) {
        final error = SBError(message: 'Failed Sending Request');
        callback(null, error);
      }
      rethrow;
    }
  }

  /// Sends Scheduled Message Now
  Future<void> sendScheduledMessageNow({
    required int scheduledMessageId,
    OnScheduledMessageSendNowCallback? callback,
  }) async {
    try {
      return _sdk.api.send(
        GroupChannelScheduledMessageSendNowRequest(
          channelType: channelType,
          channelUrl: channelUrl,
          scheduledMessageId: scheduledMessageId,
        ),
      );
    } catch (e) {
      if (callback != null) {
        callback(SBError(message: 'Failed Sending Request'));
      }

      rethrow;
    }
  }

  /// Creates scheduled file message
  Future<ScheduledFileMessage> createScheduledFileMessage(
    ScheduledFileMessageParams fileMessageParams, {
    OnScheduledMessageCallback<ScheduledFileMessage>? callback,
  }) async {
    UploadResponse? upload;

    if (fileMessageParams.uploadFile.hasBinary) {
      try {
        upload = await _sdk.api
            .send<UploadResponse>(
          ChannelScheduledFileUploadRequest(
            channelUrl: channelUrl,
            params: fileMessageParams,
          ),
        )
            .timeout(
          Duration(seconds: _sdk.options.fileTransferTimeout),
          onTimeout: () {
            logger.e('upload timeout');
            if (callback != null) {
              callback(null, SBError(code: ErrorCode.fileUploadTimeout));
            }
            throw SBError(code: ErrorCode.fileUploadTimeout);
          },
        );
        fileMessageParams.uploadFile
          ..fileSize = upload.fileSize
          ..url = upload.url;
      } catch (e) {
        if (callback != null) {
          final error = SBError(message: 'Failed Sending Request');
          callback(null, error);
        }
        rethrow;
      }
    }

    try {
      final result = await _sdk.api.send<ScheduledFileMessage>(
        GroupChannelScheduledFileMessageSendRequest(
          channelUrl: channelUrl,
          params: fileMessageParams,
        ),
      );

      if (callback != null) {
        callback(result, null);
      }
      return result;
    } catch (e) {
      if (callback != null) {
        final error = SBError(message: 'Failed Sending Request');
        callback(null, error);
      }
      rethrow;
    }
  }

  /// Updates Poll
  Future<Poll> updatePoll({
    required int pollId,
    required PollUpdateParams params,
    OnPollCallback? onCompleted,
  }) async {
    Poll poll = await _sdk.api
        .send(
      PollUpdateRequest(
        pollId: pollId,
        params: params,
      ),
    )
        .onError((error, stackTrace) {
      if (onCompleted != null) {
        onCompleted(null, SBError(message: 'Failed updating poll'));
      }
      throw SBError(message: "Failed updating poll");
    });
    if (onCompleted != null) {
      onCompleted(poll, null);
    }
    return poll;
  }

  /// Delete Poll
  Future<void> deletePoll({
    required int pollId,
    OnCompleteCallback? onCompleted,
  }) async {
    try {
      await _sdk.api.send(PollDeleteRequest(pollId: pollId));
      if (onCompleted != null) {
        onCompleted(true, null);
      }
    } catch (e) {
      if (onCompleted != null) {
        onCompleted(false, SBError(message: 'Failed deleting Poll'));
      }
      throw SBError(message: e.toString());
    }
    return;
  }

  /// Close Poll
  Future<Poll> closePoll({
    required int pollId,
    OnPollCallback? onCompleted,
  }) async {
    Poll poll = await _sdk.api.send(PollCloseRequest(pollId: pollId)).onError((error, stackTrace) {
      if (onCompleted != null) {
        onCompleted(null, SBError(message: 'Failed closing poll'));
      }
      throw SBError(message: "Failed closing poll");
    });
    if (onCompleted != null) {
      onCompleted(poll, null);
    }
    return poll;
  }

  /// Add Poll Option
  Future<Poll> addPollOption({
    required int pollId,
    required String optionText,
    OnPollCallback? onCompleted,
  }) async {
    Poll poll = await _sdk.api
        .send(
      PollOptionAddRequest(
        pollId: pollId,
        text: optionText,
        channelUrl: channelUrl,
        channelType: channelType,
      ),
    )
        .onError((error, stackTrace) {
      if (onCompleted != null) {
        onCompleted(null, SBError(message: 'Failed adding poll option'));
      }
      throw SBError(message: "Failed adding poll option");
    });
    if (onCompleted != null) {
      onCompleted(poll, null);
    }
    return poll;
  }

  /// Update Poll Option
  Future<Poll> updatePollOption({
    required int pollId,
    required int pollOptionId,
    required String optionText,
    OnPollCallback? onCompleted,
  }) async {
    Poll poll = await _sdk.api
        .send(
      PollOptionUpdateRequest(
        pollId: pollId,
        pollOptionId: pollOptionId,
        text: optionText,
      ),
    )
        .onError((error, stackTrace) {
      if (onCompleted != null) {
        onCompleted(null, SBError(message: 'Failed updating poll option'));
      }
      throw SBError(message: "Failed updating poll option");
    });

    if (onCompleted != null) {
      onCompleted(poll, null);
    }
    return poll;
  }

  /// Delete Poll Option
  Future<void> deletePollOption({
    required int pollId,
    required int pollOptionId,
    OnCompleteCallback? onCompleted,
  }) async {
    try {
      await _sdk.api.send(PollOptionDeleteRequest(
        pollId: pollId,
        pollOptionId: pollOptionId,
      ));
      if (onCompleted != null) {
        onCompleted(true, null);
      }
    } catch (e) {
      if (onCompleted != null) {
        onCompleted(false, SBError(message: 'Failed deleting poll opiton.'));
      }
    }
  }

  /// Cast/ Cancel Poll Vote
  Future<PollVoteEvent> votePoll({
    required int pollId,
    required List<int> pollOptionIds,
    OnPollVoteEventCallback? onCompleted,
  }) async {
    final cmd = Command.buildVotePoll(
      requestId: Uuid().v1(),
      channelType: channelType,
      channelUrl: channelUrl,
      pollId: pollId,
      pollOptionIds: pollOptionIds,
    );

    try {
      var result = await _sdk.cmdManager.sendCommand(cmd);
      if (result == null) throw SBError(message: "ERROR: NULL returned from VotePoll sendCommand");
      PollVoteEvent event = PollVoteEvent.fromJson(result.payload);

      if (onCompleted != null) {
        onCompleted(event, null);
      }

      return event;
    } catch (exception) {
      logger.e(StackTrace.current, error: [exception]);
      if (onCompleted != null) onCompleted(null, SBError(message: "Failed sending Vote Poll Request."));

      throw (SBError(message: "Failed sending Vote Poll Request."));
    }
  }
}

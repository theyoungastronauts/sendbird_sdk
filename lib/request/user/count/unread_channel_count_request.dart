import 'package:sendbird_sdk/constant/enums.dart';
import 'package:sendbird_sdk/params/group_channel_total_unread_channel_count_params.dart';
import 'package:sendbird_sdk/request/abstract/api_request.dart';
import 'package:sendbird_sdk/services/network/http_client.dart';

class UserTotalUnreadChannelCountGetRequest extends ApiRequest {
  @override
  final method = Method.get;

  UserTotalUnreadChannelCountGetRequest({
    GroupChannelTotalUnreadChannelCountParams? params,
    String? userId,
  }) : super(userId: userId) {
    url = 'users/${userId ?? state.userId}/unread_channel_count';
    final customTypes = params?.customTypes ?? [];
    final superFilter = params?.superChannelFilter ?? SuperChannelFilter.all;
    queryParams = {
      if (customTypes.isNotEmpty) 'custom_types': customTypes,
      'super_mode': groupChannelSuperFilterEnum(superFilter),
    };
  }

  @override
  Future<int> response(res) async {
    return res['unread_count'];
  }
}

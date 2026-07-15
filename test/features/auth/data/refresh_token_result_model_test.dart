import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_palladin/features/auth/data/models/refresh_token_result_model.dart';

void main() {
  test('parses the backend refresh response without login metadata', () {
    final result = RefreshTokenResultModel.fromJson({
      'accessToken': 'new-access-token',
      'refreshToken': 'new-refresh-token',
    });

    expect(result.accessToken, 'new-access-token');
    expect(result.refreshToken, 'new-refresh-token');
  });
}

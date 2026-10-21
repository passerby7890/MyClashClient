// lib/presentation/more/crisp_chat_screen.dart

import 'package:flutter/material.dart';

import '../../business/auth/user_model.dart';
import '../dashboard/widgets/customer_service_modal.dart';

/// Crisp In-App 原生即時聊天視窗 (相容層，直接橋接至 CustomerServiceModal)
class CrispChatScreen extends StatelessWidget {
  final String? crispId;
  final String? userEmail;
  final UserModel? user;

  const CrispChatScreen({
    super.key,
    this.crispId,
    this.userEmail,
    this.user,
  });

  @override
  Widget build(BuildContext context) {
    UserModel? effectiveUser = user;
    if (effectiveUser == null &&
        userEmail != null &&
        userEmail!.trim().isNotEmpty) {
      effectiveUser = UserModel(
        email: userEmail!.trim(),
        transferEnable: 0,
        u: 0,
        d: 0,
        planName: '標準會員',
      );
    }

    return CustomerServiceModal(
      crispId: crispId,
      user: effectiveUser,
    );
  }
}

// lib/presentation/dashboard/widgets/traffic_card.dart

import 'package:flutter/material.dart';
import '../../../core/i18n/i18n_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../business/auth/user_model.dart';

/// 流量狀態卡片 (TrafficCard)
/// 顯示剩餘流量百分比與到期日；流量耗盡或過期時顯示醒目紅框並發出警示
class TrafficCard extends StatelessWidget {
  final UserModel? user;
  final VoidCallback? onRenewTap;
  final VoidCallback? onDetailTap;

  const TrafficCard({
    super.key,
    required this.user,
    this.onRenewTap,
    this.onDetailTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAvailable = user?.isAvailable ?? true;
    final isExpired = user?.isExpired ?? false;
    final isDepleted = user?.isTrafficDepleted ?? false;
    final usedRatio = user?.usedPercentage ?? 0.0;

    // 當異常時外框轉為警示紅框
    final borderColor = !isAvailable
        ? AppTheme.dangerRose
        : AppTheme.darkBorder;

    final i18n = I18nService.instance;
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: borderColor,
          width: !isAvailable ? 2.0 : 1.0,
        ),
        boxShadow: !isAvailable
            ? [
                BoxShadow(
                  color: AppTheme.dangerRose.withOpacity(0.2),
                  blurRadius: 16,
                  spreadRadius: 2,
                )
              ]
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 頂部標題列與狀態徽章
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.data_usage_rounded,
                    color: !isAvailable ? AppTheme.dangerRose : AppTheme.primaryCyan,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    i18n.t('service_and_traffic'),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  if (onDetailTap != null)
                    GestureDetector(
                      onTap: onDetailTap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryCyan.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.primaryCyan.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              i18n.t('details'),
                              style: const TextStyle(
                                color: AppTheme.primaryCyan,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, size: 14, color: AppTheme.primaryCyan),
                          ],
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: !isAvailable
                          ? AppTheme.dangerRose.withOpacity(0.18)
                          : AppTheme.successEmerald.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: !isAvailable
                            ? AppTheme.dangerRose.withOpacity(0.4)
                            : AppTheme.successEmerald.withOpacity(0.4),
                      ),
                    ),
                    child: Text(
                      !isAvailable
                          ? (isExpired
                              ? i18n.t('traffic_expired')
                              : (isDepleted ? i18n.t('traffic_warning_exhausted') : i18n.t('status_error')))
                          : i18n.t('service_normal'),
                      style: TextStyle(
                        color: !isAvailable ? AppTheme.dangerRose : AppTheme.successEmerald,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 流量大數字與剩餘百分比
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user != null ? user!.remainingTrafficFormatted : '-- GB',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: !isAvailable ? AppTheme.dangerRose : Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    i18n.t('remaining_traffic'),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              Text(
                '${i18n.t("traffic_used")} ${(usedRatio * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  color: !isAvailable ? AppTheme.dangerRose : AppTheme.primaryCyan,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 現代漸層進度條
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 8,
              child: LinearProgressIndicator(
                value: usedRatio,
                backgroundColor: AppTheme.darkSurface,
                valueColor: AlwaysStoppedAnimation<Color>(
                  !isAvailable ? AppTheme.dangerRose : AppTheme.primaryCyan,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // 數據詳情格網 (已用、總計、到期日)
          Row(
            children: [
              _buildDetailItem(
                label: i18n.t('used_traffic'),
                value: user?.usedTrafficFormatted ?? '--',
              ),
              Container(width: 1, height: 26, color: AppTheme.darkBorder),
              _buildDetailItem(
                label: i18n.t('total_traffic'),
                value: user?.totalTrafficFormatted ?? '--',
              ),
              Container(width: 1, height: 26, color: AppTheme.darkBorder),
              _buildDetailItem(
                label: i18n.t('expire_time'),
                value: user?.expiredDateFormatted ?? i18n.t('never_expire'),
                highlight: isExpired,
              ),
            ],
          ),

          // 若已過期或流量耗盡，展示告警橫條與續費按鈕
          if (!isAvailable) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.dangerRose.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: AppTheme.dangerRose, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isExpired ? i18n.t('traffic_warning_expired') : i18n.t('traffic_warning_exhausted'),
                      style: const TextStyle(color: AppTheme.dangerRose, fontSize: 12),
                    ),
                  ),
                  if (onRenewTap != null)
                    GestureDetector(
                      onTap: onRenewTap,
                      child: Text(
                        '${i18n.t('renew_now')} >',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailItem({
    required String label,
    required String value,
    bool highlight = false,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: highlight ? AppTheme.dangerRose : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

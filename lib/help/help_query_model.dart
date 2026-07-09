import 'package:cloud_firestore/cloud_firestore.dart';

enum QueryStatus { pending, inProgress, resolved }

extension QueryStatusX on QueryStatus {
  String get value {
    switch (this) {
      case QueryStatus.pending:
        return 'pending';
      case QueryStatus.inProgress:
        return 'in_progress';
      case QueryStatus.resolved:
        return 'resolved';
    }
  }

  String get label {
    switch (this) {
      case QueryStatus.pending:
        return 'Pending';
      case QueryStatus.inProgress:
        return 'In Progress';
      case QueryStatus.resolved:
        return 'Resolved';
    }
  }

  static QueryStatus fromValue(String? value) {
    switch (value) {
      case 'in_progress':
        return QueryStatus.inProgress;
      case 'resolved':
        return QueryStatus.resolved;
      case 'pending':
      default:
        return QueryStatus.pending;
    }
  }
}

const List<String> kHelpQueryCategories = [
  'Payment Issue',
  'Product Listing',
  'Account & Login',
  'Report a User',
  'Chat / Messaging',
  'App Bug',
  'Other',
];

class HelpQuery {
  final String id;
  final String userId;
  final String userName;
  final String userEmail;
  final String userPhone;
  final String category;
  final String subject;
  final String message;
  final QueryStatus status;
  final String adminNote;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? contactedAt;

  const HelpQuery({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.userPhone,
    required this.category,
    required this.subject,
    required this.message,
    required this.status,
    required this.adminNote,
    required this.createdAt,
    required this.updatedAt,
    required this.contactedAt,
  });

  factory HelpQuery.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return HelpQuery(
      id: doc.id,
      userId: (data['userId'] as String?) ?? '',
      userName: (data['userName'] as String?) ?? 'Unknown',
      userEmail: (data['userEmail'] as String?) ?? '',
      userPhone: (data['userPhone'] as String?) ?? '',
      category: (data['category'] as String?) ?? 'Other',
      subject: (data['subject'] as String?) ?? '',
      message: (data['message'] as String?) ?? '',
      status: QueryStatusX.fromValue(data['status'] as String?),
      adminNote: (data['adminNote'] as String?) ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      contactedAt: (data['contactedAt'] as Timestamp?)?.toDate(),
    );
  }
}
class InvestorDocument {
  final String id;
  final String name;
  final String category; // contract | agreement | kyc | other
  final String signedUrl;
  final DateTime? uploadedAt;
  final int? fileSizeKb;
  final bool isDemo;

  const InvestorDocument({
    required this.id,
    required this.name,
    required this.category,
    required this.signedUrl,
    this.uploadedAt,
    this.fileSizeKb,
    this.isDemo = false,
  });

  factory InvestorDocument.fromSupabase(
    Map<String, dynamic> j, {
    required String signedUrl,
  }) =>
      InvestorDocument(
        id: (j['id'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        category: (j['doc_type'] ?? 'other') as String,
        signedUrl: signedUrl,
        uploadedAt: j['uploaded_at'] != null
            ? DateTime.parse(j['uploaded_at'].toString())
            : null,
        fileSizeKb: j['file_size_kb'] as int?,
      );
}

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import '../utils/network_utils.dart';

class PastQuestion {
  final int id;
  final String name;
  final String exam;
  final String subject;
  final String file;
  final int year;
  final String createdAt;

  PastQuestion({
    required this.id,
    required this.name,
    required this.exam,
    required this.subject,
    required this.file,
    required this.year,
    required this.createdAt,
  });

  factory PastQuestion.fromJson(Map<String, dynamic> json) {
    return PastQuestion(
      id: json['id'] is int ? json['id'] : int.parse(json['id'].toString()),
      name: json['name'] ?? '',
      exam: json['exam'] ?? '',
      subject: json['subject'] ?? '',
      file: json['file'] ?? '',
      year: json['year'] is int
          ? json['year']
          : int.parse(json['year'].toString()),
      createdAt: json['created_at'] ?? '',
    );
  }
}

class PastQuestionsPage extends StatefulWidget {
  const PastQuestionsPage({super.key});

  @override
  State<PastQuestionsPage> createState() => _PastQuestionsPageState();
}

class _PastQuestionsPageState extends State<PastQuestionsPage> {
  List<PastQuestion> _pastQuestions = [];
  bool _isLoading = false;
  StreamSubscription? _connectivitySubscription;
  String? _selectedExam;
  String? _selectedSubject;
  String? _selectedYear;
  List<String> _exams = [];
  List<String> _subjects = [];
  List<String> _years = [];

  @override
  void initState() {
    super.initState();
    _initConnectivity();
    _fetchPastQuestions();
  }

  Future<void> _initConnectivity() async {
    await _checkInternetConnection();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      result,
    ) async {
      await _checkInternetConnection();
    });
  }

  Future<bool> _checkInternetConnection() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (e) {
      return false;
    }
  }

  Future<void> _fetchPastQuestions() async {
    if (!await _checkInternetConnection()) {
      if (mounted) {
        showNetworkErrorSnackBar(
          context,
          Exception('No internet connection'),
          fontSize: _getResponsiveFontSize(context, 14),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final api = ApiService();
      final data = await api.get('past-questions');
      if (data['status'] == 'success' && data['data'] != null) {
        final questions = (data['data'] as List)
            .map((q) => PastQuestion.fromJson(q))
            .toList();

        // Extract unique exams, subjects, and years
        final exams = <String>{};
        final subjects = <String>{};
        final years = <String>{};

        for (var q in questions) {
          exams.add(q.exam);
          subjects.add(q.subject);
          years.add(q.year.toString());
        }

        setState(() {
          _pastQuestions = questions;
          _exams = exams.toList()..sort();
          _subjects = subjects.toList()..sort();
          _years = years.toList()
            ..sort((a, b) => int.parse(b).compareTo(int.parse(a)));
        });
      }
    } catch (e) {
      if (mounted) {
        showNetworkErrorSnackBar(
          context,
          e,
          fontSize: _getResponsiveFontSize(context, 14),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<PastQuestion> _getFilteredQuestions() {
    return _pastQuestions.where((q) {
      if (_selectedExam != null && q.exam != _selectedExam) return false;
      if (_selectedSubject != null && q.subject != _selectedSubject) {
        return false;
      }
      if (_selectedYear != null && q.year.toString() != _selectedYear) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _viewPDF(String filePath) async {
    try {
      final url = 'https://mkdata.com.ng$filePath';
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open PDF'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _downloadPDF(String filePath, String fileName) async {
    try {
      final url = 'https://mkdata.com.ng$filePath';
      if (await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Download started'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not download PDF'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  double _getResponsiveFontSize(BuildContext context, double baseSize) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth < 360) {
      return baseSize * 0.9;
    } else if (screenWidth < 400) {
      return baseSize * 0.95;
    } else if (screenWidth < 500) {
      return baseSize * 1.0;
    } else {
      return baseSize * 1.05;
    }
  }

  double _getResponsivePadding(BuildContext context, double basePadding) {
    final screenWidth = MediaQuery.of(context).size.width;
    final scaleFactor = screenWidth / 375;
    return basePadding * scaleFactor.clamp(0.8, 1.2);
  }

  double _getResponsiveSpacing(BuildContext context, double baseSpacing) {
    final screenWidth = MediaQuery.of(context).size.width;
    final scaleFactor = screenWidth / 375;
    return baseSpacing * scaleFactor.clamp(0.8, 1.2);
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filteredQuestions = _getFilteredQuestions();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFFce4323),
        elevation: 0,
        title: Text(
          'Past Questions',
          style: TextStyle(
            color: Colors.white,
            fontSize: _getResponsiveFontSize(context, 18),
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: Colors.white,
            size: _getResponsiveFontSize(context, 24),
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(
                  color: const Color(0xFFce4323),
                ),
              )
            : SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.all(_getResponsivePadding(context, 16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Exam Filter
                      Text(
                        'Filter by Exam',
                        style: TextStyle(
                          fontSize: _getResponsiveFontSize(context, 14),
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      SizedBox(height: _getResponsiveSpacing(context, 8)),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip('All', _selectedExam == null, () {
                              setState(() {
                                _selectedExam = null;
                              });
                            }),
                            ..._exams.map((exam) {
                              return _buildFilterChip(
                                exam,
                                _selectedExam == exam,
                                () {
                                  setState(() {
                                    _selectedExam = exam;
                                  });
                                },
                              );
                            }),
                          ],
                        ),
                      ),
                      SizedBox(height: _getResponsiveSpacing(context, 16)),

                      // Subject Filter
                      Text(
                        'Filter by Subject',
                        style: TextStyle(
                          fontSize: _getResponsiveFontSize(context, 14),
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      SizedBox(height: _getResponsiveSpacing(context, 8)),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip(
                              'All',
                              _selectedSubject == null,
                              () {
                                setState(() {
                                  _selectedSubject = null;
                                });
                              },
                            ),
                            ..._subjects.map((subject) {
                              return _buildFilterChip(
                                subject,
                                _selectedSubject == subject,
                                () {
                                  setState(() {
                                    _selectedSubject = subject;
                                  });
                                },
                              );
                            }),
                          ],
                        ),
                      ),
                      SizedBox(height: _getResponsiveSpacing(context, 16)),

                      // Year Filter
                      Text(
                        'Filter by Year',
                        style: TextStyle(
                          fontSize: _getResponsiveFontSize(context, 14),
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      SizedBox(height: _getResponsiveSpacing(context, 8)),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip('All', _selectedYear == null, () {
                              setState(() {
                                _selectedYear = null;
                              });
                            }),
                            ..._years.map((year) {
                              return _buildFilterChip(
                                year,
                                _selectedYear == year,
                                () {
                                  setState(() {
                                    _selectedYear = year;
                                  });
                                },
                              );
                            }),
                          ],
                        ),
                      ),
                      SizedBox(height: _getResponsiveSpacing(context, 24)),

                      // Past Questions List
                      Text(
                        'Past Questions (${filteredQuestions.length})',
                        style: TextStyle(
                          fontSize: _getResponsiveFontSize(context, 16),
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      SizedBox(height: _getResponsiveSpacing(context, 12)),

                      if (filteredQuestions.isEmpty)
                        Container(
                          padding: EdgeInsets.all(
                            _getResponsivePadding(context, 16),
                          ),
                          child: Center(
                            child: Text(
                              'No past questions found',
                              style: TextStyle(
                                fontSize: _getResponsiveFontSize(context, 14),
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filteredQuestions.length,
                          itemBuilder: (context, index) {
                            final question = filteredQuestions[index];
                            return Container(
                              margin: EdgeInsets.only(
                                bottom: _getResponsiveSpacing(context, 12),
                              ),
                              padding: EdgeInsets.all(
                                _getResponsivePadding(context, 12),
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                  color: Colors.grey.shade300,
                                  width: 1,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.shade200,
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Header with name
                                  Text(
                                    question.name,
                                    style: TextStyle(
                                      fontSize: _getResponsiveFontSize(
                                        context,
                                        14,
                                      ),
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  SizedBox(
                                    height: _getResponsiveSpacing(context, 8),
                                  ),

                                  // Details row
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Exam: ${question.exam}',
                                              style: TextStyle(
                                                fontSize:
                                                    _getResponsiveFontSize(
                                                      context,
                                                      12,
                                                    ),
                                                color: Colors.grey.shade700,
                                              ),
                                            ),
                                            SizedBox(
                                              height: _getResponsiveSpacing(
                                                context,
                                                4,
                                              ),
                                            ),
                                            Text(
                                              'Subject: ${question.subject}',
                                              style: TextStyle(
                                                fontSize:
                                                    _getResponsiveFontSize(
                                                      context,
                                                      12,
                                                    ),
                                                color: Colors.grey.shade700,
                                              ),
                                            ),
                                            SizedBox(
                                              height: _getResponsiveSpacing(
                                                context,
                                                4,
                                              ),
                                            ),
                                            Text(
                                              'Year: ${question.year}',
                                              style: TextStyle(
                                                fontSize:
                                                    _getResponsiveFontSize(
                                                      context,
                                                      12,
                                                    ),
                                                color: Colors.grey.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Action buttons
                                      Column(
                                        children: [
                                          // View button
                                          IconButton(
                                            icon: Icon(
                                              Icons.visibility,
                                              color: const Color(0xFFce4323),
                                              size: _getResponsiveFontSize(
                                                context,
                                                24,
                                              ),
                                            ),
                                            onPressed: () {
                                              _viewPDF(question.file);
                                            },
                                            tooltip: 'View PDF',
                                          ),
                                          // Download button
                                          IconButton(
                                            icon: Icon(
                                              Icons.download,
                                              color: const Color(0xFFce4323),
                                              size: _getResponsiveFontSize(
                                                context,
                                                24,
                                              ),
                                            ),
                                            onPressed: () {
                                              _downloadPDF(
                                                question.file,
                                                question.name,
                                              );
                                            },
                                            tooltip: 'Download PDF',
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    return Padding(
      padding: EdgeInsets.only(right: _getResponsiveSpacing(context, 8)),
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: _getResponsiveFontSize(context, 12),
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        onSelected: (_) => onTap(),
        selected: isSelected,
        backgroundColor: Colors.grey.shade100,
        selectedColor: const Color(0xFFce4323),
        side: BorderSide(
          color: isSelected ? const Color(0xFFce4323) : Colors.grey.shade300,
          width: 1,
        ),
      ),
    );
  }
}

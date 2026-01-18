import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../services/api_service.dart';

class ContactPage extends StatefulWidget {
  const ContactPage({super.key});

  @override
  State<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends State<ContactPage> {
  late final ApiService _apiService;

  Map<String, dynamic> _contactData = {};
  List<Map<String, dynamic>> _faqData = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _apiService = ApiService();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final contactData = await _apiService.getSiteSettings();
      final faqData = await _apiService.getFAQ();

      print('[ContactPage] Contact Data: $contactData');
      print('[ContactPage] FAQ Data: $faqData');

      if (mounted) {
        setState(() {
          _contactData = contactData;
          _faqData = faqData;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      print('Error loading data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load contact information: ${e.toString()}';
        });
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _launchURL(String urlString, BuildContext context) async {
    try {
      final Uri url = Uri.parse(urlString);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        if (context.mounted) {
          _showError(context, 'Could not launch $urlString');
        }
      }
    } catch (e) {
      print('Error launching URL: $e');
      if (context.mounted) {
        _showError(context, 'Error: ${e.toString()}');
      }
    }
  }

  Future<void> _makePhoneCall(String phoneNumber, BuildContext context) async {
    try {
      // Clean phone number - remove spaces, dashes, and extra characters
      String cleanNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');

      // If number doesn't start with +, assume it's a local number
      if (!cleanNumber.startsWith('+')) {
        cleanNumber = '+$cleanNumber';
      }

      print('[ContactPage] Calling: $cleanNumber');

      final Uri uri = Uri(scheme: 'tel', path: cleanNumber);
      if (!await launchUrl(uri)) {
        if (context.mounted) {
          _showError(context, 'Could not make phone call');
        }
      }
    } catch (e) {
      print('Error making phone call: $e');
      if (context.mounted) {
        _showError(context, 'Error: ${e.toString()}');
      }
    }
  }

  Future<void> _sendEmail(String email, BuildContext context) async {
    try {
      final Uri uri = Uri(scheme: 'mailto', path: email);
      if (!await launchUrl(uri)) {
        if (context.mounted) {
          _showError(context, 'Could not send email');
        }
      }
    } catch (e) {
      print('Error sending email: $e');
      if (context.mounted) {
        _showError(context, 'Error: ${e.toString()}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help Center'),
        backgroundColor: const Color(0xFFce4323),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(_error!),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _isLoading = true;
                      });
                      _loadData();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : Padding(
              padding: EdgeInsets.only(bottom: kBottomNavigationBarHeight),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top gradient header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFce4323), Color(0xFFce4323)],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: const [
                              Expanded(
                                child: Text(
                                  'Hi Dear, how can we help you today?',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              SizedBox(width: 12),
                              CircleAvatar(
                                radius: 28,
                                backgroundColor: Colors.white24,
                                child: Icon(
                                  Icons.support_agent,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Column(
                        children: [
                          // FAQ card
                          Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                children: [
                                  const Center(
                                    child: Text(
                                      'Frequently Asked Questions',
                                      style: TextStyle(
                                        color: Color(0xFFce4323),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Divider(),
                                  ..._buildFAQTiles(),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Quick Actions card
                          Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12.0,
                                vertical: 8,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceAround,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _sendEmail(
                                      _contactData['email'] ?? '',
                                      context,
                                    ),
                                    icon: const Icon(
                                      Icons.email,
                                      color: Color(0xFFce4323),
                                    ),
                                    label: const Text(
                                      'Email',
                                      style: TextStyle(
                                        color: Color(0xFFce4323),
                                      ),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _makePhoneCall(
                                      _contactData['phone'] ?? '',
                                      context,
                                    ),
                                    icon: const Icon(
                                      Icons.phone,
                                      color: Color(0xFFce4323),
                                    ),
                                    label: const Text(
                                      'Call',
                                      style: TextStyle(
                                        color: Color(0xFFce4323),
                                      ),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _launchURL(
                                      'https://wa.me/${_contactData['whatsapp']}',
                                      context,
                                    ),
                                    icon: const Icon(
                                      Icons.chat,
                                      color: Color(0xFFce4323),
                                    ),
                                    label: const Text(
                                      'Chat',
                                      style: TextStyle(
                                        color: Color(0xFFce4323),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Contact Us card
                          Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  const Center(
                                    child: Text(
                                      'Contact Us',
                                      style: TextStyle(
                                        color: Color(0xFFce4323),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ListTile(
                                    leading: const CircleAvatar(
                                      backgroundColor: Color(0xFFce4323),
                                      child: Icon(
                                        Icons.email,
                                        color: Colors.white,
                                      ),
                                    ),
                                    title: const Text('Email'),
                                    subtitle: Text(_contactData['email'] ?? ''),
                                    onTap: () => _sendEmail(
                                      _contactData['email'] ?? '',
                                      context,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  // Follow Us card
                                  Card(
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12.0,
                                        vertical: 12,
                                      ),
                                      child: Column(
                                        children: [
                                          const Center(
                                            child: Text(
                                              'Follow Us',
                                              style: TextStyle(
                                                color: Color(0xFFce4323),
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceEvenly,
                                            children: [
                                              _buildSocialButton(
                                                FontAwesomeIcons.whatsapp,
                                                'https://wa.me/${_contactData['whatsapp']}',
                                                context,
                                              ),
                                              _buildSocialButton(
                                                FontAwesomeIcons.facebook,
                                                _contactData['facebook'] ??
                                                    'https://facebook.com/',
                                                context,
                                              ),
                                              _buildSocialButton(
                                                FontAwesomeIcons.instagram,
                                                _contactData['instagram'] ??
                                                    'https://instagram.com/',
                                                context,
                                              ),
                                              _buildSocialButton(
                                                FontAwesomeIcons.twitter,
                                                _contactData['twitter'] ??
                                                    'https://twitter.com/',
                                                context,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  ListTile(
                                    leading: const CircleAvatar(
                                      backgroundColor: Color(0xFFce4323),
                                      child: Icon(
                                        Icons.phone,
                                        color: Colors.white,
                                      ),
                                    ),
                                    title: const Text('Phone'),
                                    subtitle: Text(_contactData['phone'] ?? ''),
                                    onTap: () => _makePhoneCall(
                                      _contactData['phone'] ?? '',
                                      context,
                                    ),
                                  ),
                                  ListTile(
                                    leading: const CircleAvatar(
                                      backgroundColor: Color(0xFFce4323),
                                      child: Icon(
                                        Icons.chat,
                                        color: Colors.white,
                                      ),
                                    ),
                                    title: const Text('Live Chat'),
                                    subtitle: const Text(
                                      'Chat with our support team',
                                    ),
                                    onTap: () => _launchURL(
                                      'https://wa.me/${_contactData['whatsapp']}',
                                      context,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  List<Widget> _buildFAQTiles() {
    List<Widget> tiles = [];
    for (int i = 0; i < _faqData.length; i++) {
      final faq = _faqData[i];
      tiles.add(
        ExpansionTile(
          title: Text(faq['question'] ?? ''),
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text(faq['answer'] ?? ''),
            ),
          ],
        ),
      );
      if (i < _faqData.length - 1) {
        tiles.add(const Divider());
      }
    }
    return tiles;
  }

  Widget _buildSocialButton(IconData icon, String url, BuildContext context) {
    return IconButton(
      onPressed:
          (url.isEmpty ||
              url == 'https://wa.me/' ||
              url == 'https://facebook.com/' ||
              url == 'https://twitter.com/' ||
              url == 'https://instagram.com/')
          ? null
          : () => _launchURL(url, context),
      icon: FaIcon(
        icon,
        color:
            (url.isEmpty ||
                url == 'https://wa.me/' ||
                url == 'https://facebook.com/' ||
                url == 'https://twitter.com/' ||
                url == 'https://instagram.com/')
            ? Colors.grey
            : const Color(0xFFce4323),
      ),
    );
  }
}

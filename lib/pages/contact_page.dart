import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class ContactPage extends StatelessWidget {
  const ContactPage({super.key});

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
      final Uri uri = Uri(scheme: 'tel', path: phoneNumber);
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
      body: Padding(
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
                        child: Icon(Icons.support_agent, color: Colors.white),
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
                          ExpansionTile(
                            title: const Text(
                              'What Are The Codes For Checking Data Balance?',
                            ),
                            children: const [
                              Padding(
                                padding: EdgeInsets.all(12.0),
                                child: Text(
                                  'Dial *123# to check your data balance or use the mobile app.',
                                ),
                              ),
                            ],
                          ),
                          const Divider(),
                          ExpansionTile(
                            title: const Text('How Do I Fund My Wallet?'),
                            children: const [
                              Padding(
                                padding: EdgeInsets.all(12.0),
                                child: Text(
                                  'Use your bank transfer, PoS, or card to fund your wallet.',
                                ),
                              ),
                            ],
                          ),
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
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          TextButton.icon(
                            onPressed: () =>
                                _sendEmail('Officialmkdata@gmail.com', context),
                            icon: const Icon(
                              Icons.email,
                              color: Color(0xFFce4323),
                            ),
                            label: const Text(
                              'Email',
                              style: TextStyle(color: Color(0xFFce4323)),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () =>
                                _makePhoneCall('09070188006', context),
                            icon: const Icon(
                              Icons.phone,
                              color: Color(0xFFce4323),
                            ),
                            label: const Text(
                              'Call',
                              style: TextStyle(color: Color(0xFFce4323)),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _launchURL(
                              'https://wa.me/09070188006',
                              context,
                            ),
                            icon: const Icon(
                              Icons.chat,
                              color: Color(0xFFce4323),
                            ),
                            label: const Text(
                              'Chat',
                              style: TextStyle(color: Color(0xFFce4323)),
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
                              child: Icon(Icons.email, color: Colors.white),
                            ),
                            title: const Text('Email'),
                            subtitle: const Text('Officialmkdata@gmail.com'),
                            onTap: () =>
                                _sendEmail('Officialmkdata@gmail.com', context),
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
                                      IconButton(
                                        onPressed: () => _launchURL(
                                          'https://wa.me/09070188006',
                                          context,
                                        ),
                                        icon: const FaIcon(
                                          FontAwesomeIcons.whatsapp,
                                          color: Color(0xFFce4323),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => _launchURL(
                                          'https://facebook.com/',
                                          context,
                                        ),
                                        icon: const FaIcon(
                                          FontAwesomeIcons.facebook,
                                          color: Color(0xFFce4323),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => _launchURL(
                                          'https://instagram.com/',
                                          context,
                                        ),
                                        icon: const FaIcon(
                                          FontAwesomeIcons.instagram,
                                          color: Color(0xFFce4323),
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () => _launchURL(
                                          'https://twitter.com/',
                                          context,
                                        ),
                                        icon: const FaIcon(
                                          FontAwesomeIcons.twitter,
                                          color: Color(0xFFce4323),
                                        ),
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
                              child: Icon(Icons.phone, color: Colors.white),
                            ),
                            title: const Text('Phone'),
                            subtitle: const Text('09070188006'),
                            onTap: () => _makePhoneCall('09070188006', context),
                          ),
                          ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Color(0xFFce4323),
                              child: Icon(Icons.chat, color: Colors.white),
                            ),
                            title: const Text('Live Chat'),
                            subtitle: const Text('Chat with our support team'),
                            onTap: () => _launchURL(
                              'https://wa.me/09070188006',
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
    ));
  }
}

import 'package:flutter/material.dart';
import 'complete_profile_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final TextEditingController _phoneController = TextEditingController();
  String _selectedCountryCode = '+91';

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _onNext() {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your phone number'),
          backgroundColor: Color(0xFF1B4EBA),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CompleteProfileScreen(
          phoneNumber: '$_selectedCountryCode $phone',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 80),
              Center(
                child: SizedBox(
                  width: 120,
                  height: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        left: 20,
                        top: 20,
                        child: Container(
                          width: 65,
                          height: 65,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1B4EBA),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(20),
                              topRight: Radius.circular(20),
                              bottomLeft: Radius.circular(20),
                              bottomRight: Radius.zero,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF1B4EBA).withValues(alpha: 0.3),
                                blurRadius: 10,
                                offset: const Offset(-2, 4),
                              )
                            ],
                          ),
                          child: const Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 20,
                        bottom: 20,
                        child: Container(
                          width: 55,
                          height: 55,
                          decoration: BoxDecoration(
                            color: const Color(0xFF4285F4),
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(16),
                              topRight: Radius.circular(16),
                              bottomLeft: Radius.zero,
                              bottomRight: Radius.circular(16),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF4285F4).withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(2, 2),
                              )
                            ],
                          ),
                          child: const Icon(
                            Icons.chat_bubble_outline,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Welcome',
                style: TextStyle(
                  color: Color(0xFF171B24),
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please Sign - in to continue',
                style: TextStyle(
                  color: Color(0xFF7E8494),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 60),
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PHONE NUMBER',
                      style: TextStyle(
                        color: Color(0xFF1B4EBA),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        DropdownButton<String>(
                          value: _selectedCountryCode,
                          underline: const SizedBox(),
                          icon: const Padding(
                            padding: EdgeInsets.only(left: 4.0),
                            child: Icon(
                              Icons.keyboard_arrow_down,
                              color: Color(0xFF1B4EBA),
                              size: 20,
                            ),
                          ),
                          style: const TextStyle(
                            color: Color(0xFF171B24),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedCountryCode = newValue;
                              });
                            }
                          },
                          items: <String>['+91', '+1', '+44', '+86', '+49', '+33']
                              .map<DropdownMenuItem<String>>((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            );
                          }).toList(),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                         child: TextField(
                             controller: _phoneController,
                             keyboardType: TextInputType.phone,
                             style: TextStyle(
                               color: Theme.of(context).colorScheme.onSurface,
                               fontSize: 16,
                               fontWeight: FontWeight.bold,
                               letterSpacing: 1.0,
                             ),
                             decoration: InputDecoration(
                               hintText: '9876543210',
                               hintStyle: TextStyle(
                                 color: Theme.of(context)
                                     .colorScheme
                                     .onSurface
                                     .withValues(alpha: 0.35),
                                 fontWeight: FontWeight.normal,
                               ),
                               enabledBorder: UnderlineInputBorder(
                                 borderSide: BorderSide(
                                   color: Theme.of(context)
                                       .colorScheme
                                       .outlineVariant,
                                   width: 1.5,
                                 ),
                               ),
                              focusedBorder: UnderlineInputBorder(
                                borderSide: BorderSide(
                                  color: Color(0xFF1B4EBA),
                                  width: 2.0,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 80),
              GestureDetector(
                onTap: _onNext,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B4EBA),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1B4EBA).withValues(alpha: 0.4),
                        blurRadius: 15,
                        spreadRadius: 2,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.arrow_forward,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

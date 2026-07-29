import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/models.dart';
import '../../core/providers/database_provider.dart';

class CompleteProfileScreen extends ConsumerStatefulWidget {
  final String phoneNumber;

  const CompleteProfileScreen({super.key, required this.phoneNumber});

  @override
  ConsumerState<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends ConsumerState<CompleteProfileScreen> {
  final TextEditingController _firstNameController = TextEditingController(text: 'Jhone');
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _customPathController = TextEditingController();
  
  String? _selectedAvatarUrl;
  String? _selectedLocalPath;
  String? _base64Image;

  // Preset Avatars from Unsplash matching the user design style
  final List<Map<String, String>> _presetAvatars = [
    {
      'name': 'Jhone william',
      'url': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150',
    },
    {
      'name': 'Azar Hosseini',
      'url': 'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=150',
    },
    {
      'name': 'Phet Putrie',
      'url': 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150',
    },
    {
      'name': 'Brijmohan Mallick',
      'url': 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=150',
    },
    {
      'name': 'Steve Smith',
      'url': 'https://images.unsplash.com/photo-1519085360753-af0119f7cbe7?w=150',
    },
    {
      'name': 'Yahiro Ayuko',
      'url': 'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=150',
    },
  ];

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _customPathController.dispose();
    super.dispose();
  }

  // Choose profile photo options
  void _showImageSelector() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Choose Profile Picture',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF171B24),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                
                // Presets Grid
                const Text(
                  'CHOOSE FROM PRESETS',
                  style: TextStyle(
                    color: Color(0xFF1B4EBA),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 80,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _presetAvatars.length,
                    itemBuilder: (context, index) {
                      final item = _presetAvatars[index];
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedAvatarUrl = item['url'];
                            _selectedLocalPath = null;
                            _base64Image = null;
                          });
                          Navigator.pop(context);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 12.0),
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _selectedAvatarUrl == item['url']
                                  ? const Color(0xFF1B4EBA)
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: CircleAvatar(
                            backgroundImage: NetworkImage(item['url']!),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),

                // Custom file path option (highly reliable on desktop/Windows)
                const Text(
                  'OR ENTER CUSTOM IMAGE FILE PATH',
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
                    Expanded(
                      child: TextField(
                        controller: _customPathController,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'C:\\path\\to\\my_photo.jpg',
                          hintStyle: const TextStyle(color: Color(0xFFC4C8D3)),
                          filled: true,
                          fillColor: const Color(0xFFF4F6FA),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1B4EBA),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () async {
                        final path = _customPathController.text.trim();
                        if (path.isNotEmpty) {
                          final file = File(path);
                          if (await file.exists()) {
                            try {
                              final bytes = await file.readAsBytes();
                              // Convert and store base64 string
                              final base64Str = base64Encode(bytes);
                              if (!context.mounted) return;
                              setState(() {
                                _selectedLocalPath = path;
                                _selectedAvatarUrl = null;
                                _base64Image = base64Str;
                              });
                              Navigator.pop(context);
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to read image file: $e')),
                              );
                            }
                          } else {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('File does not exist')),
                            );
                          }
                        }
                      },
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _onContinue() async {
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();

    if (firstName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('First name cannot be empty'),
          backgroundColor: Color(0xFF1B4EBA),
        ),
      );
      return;
    }

    // Prepare profile model
    final profile = UserProfile(
      firstName: firstName,
      lastName: lastName,
      phoneNumber: widget.phoneNumber,
      profilePicPath: _selectedLocalPath ?? _selectedAvatarUrl, // Store path/URL
      profilePicBase64: _base64Image,
    );

    // If a preset avatar is chosen, we can also store a placeholder base64 or download it
    // But to keep it instant, we can simply let other peers pull it or display initials.
    
    // Save profile to database
    await ref.read(userProfileProvider.notifier).saveProfile(profile);

    // Reactive MyApp state will transition automatically to MainScreen!
    // We just need to pop this pushed screen to reveal it.
    if (mounted) {
      Navigator.popUntil(context, (route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF171B24), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'COMPLETE PROFILE',
          style: TextStyle(
            color: Color(0xFF171B24),
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.0,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 30),
              
              // Profile Picture selector
              Center(
                child: GestureDetector(
                  onTap: _showImageSelector,
                  child: Column(
                    children: [
                      Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F6FA),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFE2E6EE),
                            width: 1.5,
                          ),
                        ),
                        child: _selectedAvatarUrl != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(55),
                                child: Image.network(
                                  _selectedAvatarUrl!,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : _selectedLocalPath != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(55),
                                    child: Image.file(
                                      File(_selectedLocalPath!),
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : const Icon(
                                    Icons.add_a_photo_outlined,
                                    color: Color(0xFF7E8494),
                                    size: 36,
                                  ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Upload your profile picture',
                        style: TextStyle(
                          color: Color(0xFF7E8494),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 48),
              
              // FIRST NAME input
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'FIRST NAME',
                    style: TextStyle(
                      color: Color(0xFF1B4EBA),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _firstNameController,
                    style: const TextStyle(
                      color: Color(0xFF171B24),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Enter your first name',
                      hintStyle: TextStyle(
                        color: Color(0xFFC4C8D3),
                        fontWeight: FontWeight.normal,
                      ),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Color(0xFFE2E6EE),
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
                ],
              ),
              
              const SizedBox(height: 32),
              
              // LAST NAME input
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LAST NAME',
                    style: TextStyle(
                      color: Color(0xFF7E8494),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _lastNameController,
                    style: const TextStyle(
                      color: Color(0xFF171B24),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Enter your last name',
                      hintStyle: TextStyle(
                        color: Color(0xFFC4C8D3),
                        fontWeight: FontWeight.normal,
                      ),
                      enabledBorder: UnderlineInputBorder(
                        borderSide: BorderSide(
                          color: Color(0xFFE2E6EE),
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
                ],
              ),
              
              const SizedBox(height: 60),
              
              // Continue Button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B4EBA),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 2,
                  shadowColor: const Color(0xFF1B4EBA).withValues(alpha: 0.3),
                ),
                onPressed: _onContinue,
                child: const Text(
                  'CONTINUE',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

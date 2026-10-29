import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/novel.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/cloud_sync_service.dart';
import '../../data/storage_service.dart';
import '../../providers/library_provider.dart';
import '../novel/novel_detail_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _showEmailAuth = false;
  bool _isRegistering = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _triggerGoogleSignIn() async {
    final auth = AuthService.instance;
    final cred = await auth.signInWithGoogle();
    if (cred != null && mounted) {
      final storage = context.read<StorageService>();
      final sync = CloudSyncService.instance;
      await sync.syncFull(storage);
      if (mounted) {
        context.read<LibraryProvider>().loadLibrary();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Signed in as ${auth.displayName}! Library synced.'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    }
  }

  void _triggerEmailAuth() async {
    final auth = AuthService.instance;
    final email = _emailController.text.trim();
    final pass = _passwordController.text.trim();
    if (email.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an email and password')),
      );
      return;
    }

    final cred = _isRegistering
        ? await auth.signUpWithEmail(email, pass)
        : await auth.signInWithEmail(email, pass);

    if (cred != null && mounted) {
      final storage = context.read<StorageService>();
      await CloudSyncService.instance.syncFull(storage);
      if (mounted) {
        context.read<LibraryProvider>().loadLibrary();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Welcome, ${auth.displayName}! Library synced.'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    }
  }

  void _triggerSyncNow() async {
    final storage = context.read<StorageService>();
    final sync = CloudSyncService.instance;
    await sync.syncFull(storage);
    if (mounted) {
      context.read<LibraryProvider>().loadLibrary();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cloud sync complete! Library & reading progress updated.'),
          backgroundColor: Color(0xFF8B5CF6),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    final sync = CloudSyncService.instance;
    final libraryProvider = context.watch<LibraryProvider>();
    final storage = context.watch<StorageService>();
    final novels = libraryProvider.novels;

    return ListenableBuilder(
      listenable: Listenable.merge([auth, sync]),
      builder: (context, _) {
        final isAuthenticated = auth.isAuthenticated;

        return Scaffold(
          appBar: AppBar(
            title: const Text('My Profile & Cloud Sync', style: TextStyle(fontWeight: FontWeight.bold)),
            actions: [
              if (isAuthenticated)
                IconButton(
                  icon: sync.isSyncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFA78BFA)),
                        )
                      : const Icon(Icons.sync_rounded, color: Color(0xFFA78BFA)),
                  tooltip: 'Sync Now with Cloud',
                  onPressed: sync.isSyncing ? null : _triggerSyncNow,
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            children: [
              if (!isAuthenticated) ...[
                _buildSignedOutCard(auth),
              ] else ...[
                _buildSignedInProfileCard(auth, sync),
                const SizedBox(height: 16),
                _buildSyncStatusCard(sync),
                const SizedBox(height: 24),
                _buildCurrentlyReadingSection(novels, storage),
                const SizedBox(height: 24),
                _buildSignOutButton(auth),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSignedOutCard(AuthService auth) {
    return Card(
      color: const Color(0xFF181824),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_sync_rounded, size: 48, color: Color(0xFFA78BFA)),
            ),
            const SizedBox(height: 16),
            const Text(
              'Sign in to Novels World',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Log in with your Gmail to sync your novels, reading history, and exact chapter progress across all your devices.',
              style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.65), height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Google Sign-In Primary Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: auth.isSigningIn ? null : _triggerGoogleSignIn,
                icon: auth.isSigningIn
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87),
                      )
                    : Image.network(
                        'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                        width: 20,
                        height: 20,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.g_mobiledata, color: Colors.black87, size: 28),
                      ),
                label: Text(
                  auth.isSigningIn ? 'Signing In...' : 'Sign in with Google',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black87),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),

            if (auth.authError != null) ...[
              const SizedBox(height: 12),
              Text(
                auth.authError!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],

            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() => _showEmailAuth = !_showEmailAuth),
              child: Text(
                _showEmailAuth ? 'Hide Email Sign-In' : 'Or use Email / Password',
                style: const TextStyle(color: Color(0xFFA78BFA), fontSize: 12),
              ),
            ),

            if (_showEmailAuth) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  filled: true,
                  fillColor: const Color(0xFF101018),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  filled: true,
                  fillColor: const Color(0xFF101018),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: auth.isSigningIn ? null : _triggerEmailAuth,
                      child: Text(_isRegistering ? 'Register' : 'Log In'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() => _isRegistering = !_isRegistering),
                    child: Text(
                      _isRegistering ? 'Have an account? Log In' : 'New here? Register',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSignedInProfileCard(AuthService auth, CloudSyncService sync) {
    return Card(
      color: const Color(0xFF181824),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: const Color(0xFF8B5CF6),
              backgroundImage: auth.photoUrl != null ? NetworkImage(auth.photoUrl!) : null,
              child: auth.photoUrl == null
                  ? Text(
                      auth.displayName.isNotEmpty ? auth.displayName[0].toUpperCase() : 'U',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    auth.displayName,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    auth.email,
                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF34D399)),
                        SizedBox(width: 4),
                        Text(
                          'Cloud Sync Active',
                          style: TextStyle(fontSize: 11, color: Color(0xFF34D399), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncStatusCard(CloudSyncService sync) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_done_rounded, size: 20, color: Color(0xFFA78BFA)),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Multi-Device Cloud Backup', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                  Text(
                    sync.lastSyncTime != null
                        ? 'Last synced: ${sync.lastSyncTime!.hour.toString().padLeft(2, '0')}:${sync.lastSyncTime!.minute.toString().padLeft(2, '0')}'
                        : 'Synchronized across all your devices',
                    style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ],
          ),
          OutlinedButton(
            onPressed: sync.isSyncing ? null : _triggerSyncNow,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
            child: sync.isSyncing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFA78BFA)),
                  )
                : const Text('Sync Now', style: TextStyle(fontSize: 12, color: Color(0xFFA78BFA))),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentlyReadingSection(List<Novel> novels, StorageService storage) {
    if (novels.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF181824),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(Icons.auto_stories_outlined, size: 40, color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(height: 10),
            const Text(
              'No Novels in Cloud Library Yet',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'Novels you read will appear here with your exact progress saved to your Google account.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Your Cloud Reading List (${novels.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              'Synced to Gmail',
              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...novels.map((novel) {
          final progress = storage.getProgress(novel.id);
          final readChapters = storage.getReadChapterIds(novel.id);

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            color: const Color(0xFF181824),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => NovelDetailScreen(novel: novel)),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 50,
                        height: 70,
                        color: const Color(0xFF262636),
                        child: novel.coverUrl.isNotEmpty
                            ? Image.network(
                                novel.coverUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.menu_book, color: Colors.white30),
                              )
                            : const Icon(Icons.menu_book, color: Colors.white30),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            novel.title,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            novel.author.isNotEmpty ? novel.author : novel.sourceId,
                            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.5)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  progress != null && progress.chapterTitle != null
                                      ? 'Left off: ${progress.chapterTitle}'
                                      : (readChapters.isNotEmpty
                                          ? '${readChapters.length} chapters read'
                                          : 'Reading'),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFA78BFA),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white30, size: 20),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSignOutButton(AuthService auth) {
    return Center(
      child: TextButton.icon(
        onPressed: () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E28),
              title: const Text('Sign Out'),
              content: const Text('Are you sure you want to sign out? Your local data will remain intact.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                  child: const Text('Sign Out'),
                ),
              ],
            ),
          );
          if (confirm == true) {
            await auth.signOut();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Signed out.')),
              );
            }
          }
        },
        icon: const Icon(Icons.logout, size: 16, color: Colors.redAccent),
        label: const Text('Sign Out of Google Account', style: TextStyle(color: Colors.redAccent)),
      ),
    );
  }
}

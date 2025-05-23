import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

class ProfilePage extends StatefulWidget {
  final User user;
  const ProfilePage({Key? key, required this.user}) : super(key: key);

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _isLoading = true;
  String _name = '';
  String _email = '';
  String _phone = '';
  String? _photoUrl;
  double _balance = 0;
  double _totalIncome = 0;
  double _totalExpense = 0;
  double _weeklyGoal = 0;
  double _monthlyGoal = 0;
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadAllDetails();
  }

  Future<void> _loadAllDetails() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .get();
      final txSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .collection('transactions')
          .get();
      if (!mounted) return;
      final data = userDoc.data() ?? {};
      double income = 0, expense = 0;
      for (var d in txSnapshot.docs.map((d) => d.data())) {
        final amt = (d['amount'] as num).toDouble();
        if (d['type'] == 'income') income += amt;
        else expense += amt;
      }
      setState(() {
        _name = data['name'] as String? ?? widget.user.displayName ?? '';
        _email = data['email'] as String? ?? widget.user.email!;
        _phone = data['phone'] as String? ?? '';
        _photoUrl = data['photoUrl'] as String?;
        _totalIncome = income;
        _totalExpense = expense;
        _balance = income - expense;
        _weeklyGoal = (data['weeklyGoal'] as num?)?.toDouble() ?? 0;
        _monthlyGoal = (data['monthlyGoal'] as num?)?.toDouble() ?? 0;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _editGoals() async {
    double weekly = _weeklyGoal;
    double monthly = _monthlyGoal;
    final formKey = GlobalKey<FormState>();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Savings Goals'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: weekly.toString(),
                decoration: const InputDecoration(labelText: 'Weekly Goal (Tsh)'),
                keyboardType: TextInputType.number,
                validator: (v) => v == null || double.tryParse(v) == null ? 'Enter valid number' : null,
                onSaved: (v) => weekly = double.parse(v!),
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: monthly.toString(),
                decoration: const InputDecoration(labelText: 'Monthly Goal (Tsh)'),
                keyboardType: TextInputType.number,
                validator: (v) => v == null || double.tryParse(v) == null ? 'Enter valid number' : null,
                onSaved: (v) => monthly = double.parse(v!),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                formKey.currentState!.save();
                Navigator.pop(context);
                setState(() => _isLoading = true);
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(widget.user.uid)
                    .update({
                  'weeklyGoal': weekly,
                  'monthlyGoal': monthly,
                });
                await _loadAllDetails();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickOrChangePhoto() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text(_photoUrl == null ? 'Add Photo' : 'Change Photo')),
          ListTile(
            leading: const Icon(Icons.photo_library),
            title: const Text('Choose from Gallery'),
            onTap: () => Navigator.pop(context, 'gallery'),
          ),
          if (_photoUrl != null)
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('Remove Photo'),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('Cancel'),
            onTap: () => Navigator.pop(context),
          ),
        ],
      ),
    );
    if (action == 'gallery') {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked != null) await _uploadPhoto(File(picked.path));
    } else if (action == 'remove') {
      await _removePhoto();
    }
  }

  Future<void> _uploadPhoto(File file) async {
    try {
      setState(() => _isLoading = true);
      final ref = FirebaseStorage.instance.ref('users/${widget.user.uid}/profile.jpg');
      await ref.putFile(file);
      final url = await ref.getDownloadURL();
      await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).update({'photoUrl': url});
      await widget.user.updatePhotoURL(url);
      await _loadAllDetails();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _removePhoto() async {
    try {
      setState(() => _isLoading = true);
      final ref = FirebaseStorage.instance.ref('users/${widget.user.uid}/profile.jpg');
      await ref.delete();
      await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).update({'photoUrl': FieldValue.delete()});
      await widget.user.updatePhotoURL(null);
      await _loadAllDetails();
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _editProfile() async {
    String name = _name;
    String phone = _phone;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Profile'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: name,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                onSaved: (v) => name = v!.trim(),
              ),
              const SizedBox(height: 8),
              TextFormField(
                initialValue: phone,
                decoration: const InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone,
                onSaved: (v) => phone = v?.trim() ?? '',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (_formKey.currentState?.validate() ?? false) {
                _formKey.currentState!.save();
                Navigator.pop(context);
                setState(() => _isLoading = true);
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(widget.user.uid)
                    .update({'name': name, 'phone': phone});
                await widget.user.updateDisplayName(name);
                await _loadAllDetails();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete Account?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).delete();
      await widget.user.delete();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  String _format(double val) => NumberFormat.currency(symbol: 'Tsh ', decimalDigits: 0).format(val);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Existing avatar/name/email...
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundImage:
                  _photoUrl != null ? NetworkImage(_photoUrl!) : null,
                  child: _photoUrl == null
                      ? const Icon(Icons.person, size: 50)
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.camera_alt),
                  onPressed: _pickOrChangePhoto,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              _name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 4),
          Center(
              child: Text(_email,
                  style: const TextStyle(color: Colors.grey))),
          const SizedBox(height: 24),
          // Financial stats card
          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 2,
            child: Padding(
              padding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statColumn('Balance', _format(_balance),
                      Icons.account_balance_wallet),
                  _statColumn('Income', _format(_totalIncome),
                      Icons.arrow_downward, color: Colors.green),
                  _statColumn('Expense', _format(_totalExpense),
                      Icons.arrow_upward, color: Colors.red),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Savings Goals',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.flag),
                    title: const Text('Weekly Goal'),
                    subtitle: Text(
                      _format(_weeklyGoal),
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.flag_outlined),
                    title: const Text('Monthly Goal'),
                    subtitle: Text(
                      _format(_monthlyGoal),
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _editGoals,
                    child: const Text('Edit Goals'),
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48)),
                  ),
                ],
              ),
            ),
          ),
          // Contact info card
          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Contact Information',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const Divider(),
                  ListTile(
                      leading: const Icon(Icons.person),
                      title: const Text('Name'),
                      subtitle: Text(_name)),
                  ListTile(
                      leading: const Icon(Icons.email),
                      title: const Text('Email'),
                      subtitle: Text(_email)),
                  ListTile(
                      leading: const Icon(Icons.phone),
                      title: const Text('Phone'),
                      subtitle: Text(
                          _phone.isNotEmpty ? _phone : 'Not set')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // New Savings Goals card

          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _editProfile,
            child: const Text('Edit Profile'),
            style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _logout,
            child: const Text('Log Out'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _deleteAccount,
            child: const Text('Delete Account',
                style: TextStyle(color: Colors.red)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: const BorderSide(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statColumn(String label, String value, IconData icon,
      {Color? color}) {
    return Column(
      children: [
        Icon(icon, color: color ?? Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}

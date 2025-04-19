// main.dart
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:contacts_service/contacts_service.dart';

void main() {
  runApp(const ContactManagementApp());
}

class ContactManagementApp extends StatelessWidget {
  const ContactManagementApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Contact Management',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const ContactListScreen(),
    );
  }
}

class ContactListScreen extends StatefulWidget {
  const ContactListScreen({Key? key}) : super(key: key);

  @override
  _ContactListScreenState createState() => _ContactListScreenState();
}

class _ContactListScreenState extends State<ContactListScreen> {
  List<Contact> _contacts = [];
  List<Contact> _filteredContacts = [];
  bool _isLoading = true;
  TextEditingController _searchController = TextEditingController();
  Map<String, DateTime> _lastContactedDates = {};

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _searchController.addListener(_filterContacts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoading = true;
    });

    // Request contacts permission
    var status = await Permission.contacts.request();
    if (status.isGranted) {
      // Load contacts
      var contacts = await ContactsService.getContacts();
      await _loadLastContactedDates();

      setState(() {
        _contacts = contacts.toList();
        _filteredContacts = _contacts;
        _isLoading = false;
      });
    } else {
      // Permission denied
      setState(() {
        _isLoading = false;
      });
      _showPermissionDeniedDialog();
    }
  }

  Future<void> _loadLastContactedDates() async {
    final prefs = await SharedPreferences.getInstance();
    Set<String> contactIds = prefs.getKeys().where((key) => key.startsWith('contact_')).toSet();
    
    for (String key in contactIds) {
      String contactId = key.replaceFirst('contact_', '');
      int? timestamp = prefs.getInt(key);
      if (timestamp != null) {
        _lastContactedDates[contactId] = DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
    }
  }

  Future<void> _saveLastContactedDate(String contactId, DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('contact_$contactId', date.millisecondsSinceEpoch);
    _lastContactedDates[contactId] = date;
  }

  void _filterContacts() {
    if (_searchController.text.isEmpty) {
      setState(() {
        _filteredContacts = _contacts;
      });
    } else {
      setState(() {
        _filteredContacts = _contacts
            .where((contact) =>
                contact.displayName?.toLowerCase().contains(_searchController.text.toLowerCase()) ??
                false)
            .toList();
      });
    }
  }

  Future<void> _recordContactInteraction(Contact contact) async {
    // Generate a unique ID for the contact if it doesn't have one
    String contactId = contact.identifier ?? "${contact.displayName}-${DateTime.now().millisecondsSinceEpoch}";
    
    await _saveLastContactedDate(contactId, DateTime.now());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Recorded interaction with ${contact.displayName}')),
    );
  }

  Future<void> _deleteUncontactedContacts() async {
    DateTime threeMonthsAgo = DateTime.now().subtract(const Duration(days: 90));
    List<Contact> contactsToDelete = [];

    for (var contact in _contacts) {
      String contactId = contact.identifier ?? '';
      if (contactId.isNotEmpty) {
        DateTime? lastContacted = _lastContactedDates[contactId];
        if (lastContacted == null || lastContacted.isBefore(threeMonthsAgo)) {
          contactsToDelete.add(contact);
          // In a real app, you would also delete from device contacts
          // ContactsService.deleteContact(contact);
        }
      }
    }

    if (contactsToDelete.isNotEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Uncontacted Numbers'),
          content: Text('Do you want to delete ${contactsToDelete.length} contacts that have not been contacted in the last 3 months?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                // Actually delete the contacts
                for (var contact in contactsToDelete) {
                  await ContactsService.deleteContact(contact);
                }
                // Refresh the contact list
                await _loadContacts();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Deleted ${contactsToDelete.length} uncontacted numbers')),
                );
              },
              child: const Text('Delete'),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No uncontacted numbers to delete')),
      );
    }
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text('This app needs contacts permission to function properly.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  String _getLastContactedText(String contactId) {
    DateTime? lastContacted = _lastContactedDates[contactId];
    if (lastContacted == null) {
      return 'Never contacted';
    } else {
      return 'Last contacted: ${DateFormat('MMM dd, yyyy').format(lastContacted)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _deleteUncontactedContacts,
            tooltip: 'Delete uncontacted numbers (3+ months)',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Search contacts',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25.0),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _filteredContacts.isEmpty
                      ? const Center(child: Text('No contacts found'))
                      : ListView.builder(
                          itemCount: _filteredContacts.length,
                          itemBuilder: (context, index) {
                            Contact contact = _filteredContacts[index];
                            String contactId = contact.identifier ?? '';
                            bool isUncontacted = false;
                            
                            if (contactId.isNotEmpty) {
                              DateTime? lastContacted = _lastContactedDates[contactId];
                              DateTime threeMonthsAgo = DateTime.now().subtract(const Duration(days: 90));
                              isUncontacted = lastContacted == null || lastContacted.isBefore(threeMonthsAgo);
                            }
                            
                            return ListTile(
                              leading: CircleAvatar(
                                child: Text(contact.displayName?[0] ?? '?'),
                              ),
                              title: Text(contact.displayName ?? 'Unknown'),
                              subtitle: Text(_getLastContactedText(contactId)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isUncontacted)
                                    const Icon(Icons.warning, color: Colors.orange),
                                  IconButton(
                                    icon: const Icon(Icons.check_circle_outline),
                                    onPressed: () => _recordContactInteraction(contact),
                                    tooltip: 'Record interaction',
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
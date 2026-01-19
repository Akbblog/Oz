import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  @override
  _AdminDashboardScreenState createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final ApiService _apiService = ApiService();
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _users = [];
  bool _isLoading = true;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final stats = await _apiService.getAdminStats();
      final users = await _apiService.getAllUsers();
      setState(() {
        _stats = stats;
        _users = users;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading data: $e')),
      );
    }
  }

  Future<void> _approveUser(int userId) async {
    try {
      await _apiService.approveUser(userId);
      _loadData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User approved successfully')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error approving user: $e')),
      );
    }
  }

  Future<void> _deleteUser(int userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete User'),
        content: Text('Are you sure you want to delete this user?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _apiService.deleteUser(userId);
        _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User deleted successfully')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting user: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    if (!authProvider.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: Text('Admin Dashboard')),
        body: Center(
          child: Text('Access Denied'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Admin Dashboard'),
        backgroundColor: Color(0xFF667eea),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          IconButton(
            icon: Icon(Icons.logout),
            onPressed: () async {
              await authProvider.logout();
              Navigator.of(context).pushReplacementNamed('/login');
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Tabs
                Container(
                  color: Colors.grey[100],
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildTab(0, 'Statistics', Icons.dashboard),
                      ),
                      Expanded(
                        child: _buildTab(1, 'Users', Icons.people),
                      ),
                    ],
                  ),
                ),
                // Content
                Expanded(
                  child: _selectedTab == 0 ? _buildStatsView() : _buildUsersView(),
                ),
              ],
            ),
    );
  }

  Widget _buildTab(int index, String label, IconData icon) {
    final isSelected = _selectedTab == index;
    return InkWell(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? Color(0xFF667eea) : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? Color(0xFF667eea) : Colors.grey),
            SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Color(0xFF667eea) : Colors.grey,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsView() {
    if (_stats == null) return Center(child: Text('No data available'));

    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Stats Grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            children: [
              _buildStatCard('Total Users', _stats!['total_users'].toString(), Icons.people, Colors.blue),
              _buildStatCard('Approved Users', _stats!['approved_users'].toString(), Icons.check_circle, Colors.green),
              _buildStatCard('Pending Users', _stats!['pending_users'].toString(), Icons.pending, Colors.orange),
              _buildStatCard('Total Jobs', _stats!['total_jobs'].toString(), Icons.work, Colors.purple),
              _buildStatCard('Completed Jobs', _stats!['completed_jobs'].toString(), Icons.done_all, Colors.teal),
              _buildStatCard('Total Results', _stats!['total_results'].toString(), Icons.list, Colors.indigo),
            ],
          ),
          SizedBox(height: 24),
          // Recent Jobs
          Text(
            'Recent Jobs',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 12),
          ...(_stats!['recent_jobs'] as List).map((job) => Card(
                margin: EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(
                    job['status'] == 'completed' ? Icons.check_circle : Icons.pending,
                    color: job['status'] == 'completed' ? Colors.green : Colors.orange,
                  ),
                  title: Text(job['category']),
                  subtitle: Text('${job['username']} • ${job['status']}'),
                  trailing: Text(
                    _formatDate(job['created_at']),
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [color.withOpacity(0.7), color],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 32),
            SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsersView() {
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: _users.length,
      itemBuilder: (context, index) {
        final user = _users[index];
        return Card(
          margin: EdgeInsets.only(bottom: 12),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: user['is_approved'] ? Colors.green : Colors.orange,
              child: Icon(
                user['is_approved'] ? Icons.check : Icons.pending,
                color: Colors.white,
              ),
            ),
            title: Text(
              user['username'],
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user['email']),
                SizedBox(height: 4),
                Row(
                  children: [
                    if (user['is_admin']) ...[
                      Chip(
                        label: Text('Admin', style: TextStyle(fontSize: 10)),
                        backgroundColor: Colors.purple.shade100,
                      ),
                      SizedBox(width: 4),
                    ],
                    Chip(
                      label: Text(
                        user['is_approved'] ? 'Approved' : 'Pending',
                        style: TextStyle(fontSize: 10),
                      ),
                      backgroundColor: user['is_approved']
                          ? Colors.green.shade100
                          : Colors.orange.shade100,
                    ),
                  ],
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!user['is_approved'])
                  IconButton(
                    icon: Icon(Icons.check, color: Colors.green),
                    onPressed: () => _approveUser(user['id']),
                    tooltip: 'Approve',
                  ),
                IconButton(
                  icon: Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteUser(user['id']),
                  tooltip: 'Delete',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }
}

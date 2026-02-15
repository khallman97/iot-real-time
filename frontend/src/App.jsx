import { useState, useEffect } from 'react';
import { getUser, logout } from './services/auth';
import { initializeMqtt, unsubscribeAll } from './services/mqtt';
import { attachIotPolicy } from './services/api';
import Login from './components/Login';
import EquipmentSelector from './components/EquipmentSelector';
import RealtimeDisplay from './components/RealtimeDisplay';
import HistoryChart from './components/HistoryChart';
import './App.css';

export default function App() {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);
  const [selectedEquipment, setSelectedEquipment] = useState('');

  useEffect(() => {
    checkAuth();
  }, []);

  const checkAuth = async () => {
    const userData = await getUser();
    if (userData.authenticated) {
      setUser(userData);

      // Attach IoT policy to Cognito identity (required for WebSocket)
      try {
        await attachIotPolicy();
      } catch (error) {
        // Continue anyway - will retry on next login
      }

      // Initialize MQTT
      try {
        await initializeMqtt();
      } catch (error) {
        // Real-time updates won't work but app will load
      }
    }
    setLoading(false);
  };

  const handleLogin = async () => {
    await checkAuth();
  };

  const handleLogout = async () => {
    unsubscribeAll();
    await logout();
    setUser(null);
    setSelectedEquipment('');
  };

  const handleEquipmentSelect = (serialNumber) => {
    setSelectedEquipment(serialNumber);
  };

  if (loading) {
    return <div className="loading">Loading...</div>;
  }

  if (!user) {
    return <Login onLogin={handleLogin} />;
  }

  return (
    <div className="app">
      <header className="app-header">
        <h1>IoT Monitoring Dashboard</h1>
        <div className="user-info">
          <span>Company: {user.companyId || 'N/A'}</span>
          <span>User: {user.username}</span>
          <button onClick={handleLogout}>Logout</button>
        </div>
      </header>

      <main className="app-main">
        <div className="sidebar">
          <EquipmentSelector
            onSelect={handleEquipmentSelect}
            selected={selectedEquipment}
          />
        </div>

        <div className="content">
          <RealtimeDisplay
            companyId={user.companyId}
            serialNumber={selectedEquipment}
          />

          <HistoryChart serialNumber={selectedEquipment} />
        </div>
      </main>
    </div>
  );
}

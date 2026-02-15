import { useState, useEffect } from 'react';
import { subscribeToEquipment, unsubscribeFromEquipment } from '../services/mqtt';

export default function RealtimeDisplay({ companyId, serialNumber }) {
  const [data, setData] = useState(null);
  const [connected, setConnected] = useState(false);
  const [lastUpdate, setLastUpdate] = useState(null);

  useEffect(() => {
    if (!companyId || !serialNumber) return;

    let isMounted = true;

    const setupSubscription = async () => {
      try {
        await subscribeToEquipment(companyId, serialNumber, (message) => {
          if (!isMounted) return;
          // Extract payload from MQTT message
          const payload = message.value || message;
          setData(payload);
          setLastUpdate(new Date());
        });
        if (isMounted) {
          setConnected(true);
        }
      } catch (error) {
        console.error('Failed to subscribe:', error);
        if (isMounted) {
          setConnected(false);
        }
      }
    };

    setupSubscription();

    return () => {
      isMounted = false;
      unsubscribeFromEquipment(companyId, serialNumber);
      setConnected(false);
    };
  }, [companyId, serialNumber]);

  if (!serialNumber) {
    return (
      <div className="realtime-display">
        <h3>Real-time Data</h3>
        <p className="placeholder">Select an equipment to view live data</p>
      </div>
    );
  }

  return (
    <div className="realtime-display">
      <h3>Real-time Data - {serialNumber}</h3>

      <div className="connection-status">
        Status: {connected ? '🟢 Connected' : '🔴 Disconnected'}
      </div>

      {data ? (
        <div className="sensor-grid">
          <div className="sensor-card">
            <span className="sensor-label">Temperature</span>
            <span className="sensor-value">{data.temp ?? '--'}°C</span>
          </div>

          <div className="sensor-card">
            <span className="sensor-label">Humidity</span>
            <span className="sensor-value">{data.humidity ?? '--'}%</span>
          </div>

          <div className="sensor-card">
            <span className="sensor-label">CO2</span>
            <span className="sensor-value">{data.co2 ?? '--'} ppm</span>
          </div>

          {lastUpdate && (
            <div className="last-update">
              Last update: {lastUpdate.toLocaleTimeString()}
            </div>
          )}
        </div>
      ) : (
        <p className="placeholder">Waiting for data...</p>
      )}
    </div>
  );
}

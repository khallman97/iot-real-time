import { useState, useEffect } from 'react';
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
} from 'chart.js';
import { Line } from 'react-chartjs-2';
import { getHistory } from '../services/api';

// Register Chart.js components
ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend
);

export default function HistoryChart({ serialNumber }) {
  const [historyData, setHistoryData] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [limit, setLimit] = useState(50);

  useEffect(() => {
    if (serialNumber) {
      loadHistory();
    }
  }, [serialNumber, limit]);

  const loadHistory = async () => {
    setLoading(true);
    setError('');

    try {
      const result = await getHistory(serialNumber, { limit });
      // Reverse to show oldest first on chart
      setHistoryData((result.data || []).reverse());
    } catch (err) {
      setError('Failed to load history');
      console.error(err);
    }

    setLoading(false);
  };

  if (!serialNumber) {
    return (
      <div className="history-chart">
        <h3>Historical Data</h3>
        <p className="placeholder">Select an equipment to view history</p>
      </div>
    );
  }

  const chartData = {
    labels: historyData.map((d) =>
      new Date(d.timestamp * 1000).toLocaleTimeString()
    ),
    datasets: [
      {
        label: 'Temperature (°C)',
        data: historyData.map((d) => d.temp),
        borderColor: 'rgb(255, 99, 132)',
        backgroundColor: 'rgba(255, 99, 132, 0.5)',
        tension: 0.1,
      },
      {
        label: 'Humidity (%)',
        data: historyData.map((d) => d.humidity),
        borderColor: 'rgb(54, 162, 235)',
        backgroundColor: 'rgba(54, 162, 235, 0.5)',
        tension: 0.1,
      },
      {
        label: 'CO2 (ppm / 10)',
        data: historyData.map((d) => (d.co2 ? d.co2 / 10 : null)),
        borderColor: 'rgb(75, 192, 192)',
        backgroundColor: 'rgba(75, 192, 192, 0.5)',
        tension: 0.1,
      },
    ],
  };

  const chartOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        position: 'top',
      },
      title: {
        display: true,
        text: `Sensor History - ${serialNumber}`,
      },
    },
    scales: {
      y: {
        beginAtZero: false,
      },
    },
  };

  return (
    <div className="history-chart">
      <h3>Historical Data</h3>

      <div className="history-controls">
        <label>
          Records:
          <select value={limit} onChange={(e) => setLimit(Number(e.target.value))}>
            <option value={25}>25</option>
            <option value={50}>50</option>
            <option value={100}>100</option>
          </select>
        </label>
        <button onClick={loadHistory} disabled={loading}>
          {loading ? 'Loading...' : 'Refresh'}
        </button>
      </div>

      {error && <div className="error">{error}</div>}

      {historyData.length > 0 ? (
        <div className="chart-container">
          <Line data={chartData} options={chartOptions} />
        </div>
      ) : (
        <p className="placeholder">
          {loading ? 'Loading history...' : 'No historical data available'}
        </p>
      )}
    </div>
  );
}

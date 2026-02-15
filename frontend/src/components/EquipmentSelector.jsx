import { useState, useEffect } from 'react';
import { getEquipment } from '../services/api';

export default function EquipmentSelector({ onSelect, selected }) {
  const [equipment, setEquipment] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    loadEquipment();
  }, []);

  const loadEquipment = async () => {
    setLoading(true);
    setError('');

    try {
      const data = await getEquipment();
      setEquipment(data.equipment || []);
    } catch (err) {
      setError('Failed to load equipment');
      console.error(err);
    }

    setLoading(false);
  };

  if (loading) {
    return <div className="equipment-selector">Loading equipment...</div>;
  }

  if (error) {
    return (
      <div className="equipment-selector">
        <div className="error">{error}</div>
        <button onClick={loadEquipment}>Retry</button>
      </div>
    );
  }

  if (equipment.length === 0) {
    return <div className="equipment-selector">No equipment found</div>;
  }

  return (
    <div className="equipment-selector">
      <label htmlFor="equipment-select">Select Equipment:</label>
      <select
        id="equipment-select"
        value={selected || ''}
        onChange={(e) => onSelect(e.target.value)}
      >
        <option value="">-- Select --</option>
        {equipment.map((eq) => (
          <option key={eq.serial_number} value={eq.serial_number}>
            {eq.name || eq.serial_number} ({eq.serial_number})
          </option>
        ))}
      </select>
    </div>
  );
}

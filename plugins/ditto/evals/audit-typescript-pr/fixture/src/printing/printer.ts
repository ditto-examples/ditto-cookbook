// Sends a ticket to the kitchen printer of this tablet's station.
// Rejects when the printer is offline or out of paper.
export async function printTicket(order: unknown): Promise<void> {
  const response = await fetch('http://192.0.2.10/print', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(order),
  });
  if (!response.ok) throw new Error(`Printer error ${response.status}`);
}

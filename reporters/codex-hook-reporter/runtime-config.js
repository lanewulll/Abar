export const DEFAULT_SERVER_PORT = 3987;

export function serverPort(environment = process.env) {
  const value = Number(environment.ABAR_SERVER_PORT);
  return Number.isInteger(value) && value > 0 && value <= 65535
    ? value
    : DEFAULT_SERVER_PORT;
}

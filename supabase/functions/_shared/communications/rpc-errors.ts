export function rpcSqlstateHttpStatus(code: string | undefined): number {
  switch (code) {
    case "28000":
      return 401;
    case "42501":
      return 403;
    case "23505":
      return 409;
    case "22023":
    case "23514":
      return 400;
    default:
      return 500;
  }
}

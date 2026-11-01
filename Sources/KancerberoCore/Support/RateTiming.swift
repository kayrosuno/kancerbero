import Foundation

/// Decide si dos muestras consecutivas forman una ventana de tasas válida.
///
/// Las tasas son deltas de contadores divididos por el tiempo real transcurrido,
/// así que una cadencia lenta (5 s, o los 10 s que acepta el daemon) es tan
/// válida como una rápida: el límite solo descarta una base de comparación
/// obsoleta (pausa, desconexión del daemon, suspensión del Mac). El bucle duerme
/// *después* de recolectar, así que la separación real es cadencia + duración
/// de la recolección; de ahí el margen.
public enum RateTiming {
    /// Para llamadas que no conocen la cadencia (petición puntual al daemon,
    /// CLI de KancerberoProbe): sigue descartando bases realmente obsoletas.
    private static let fallbackMaximumGap: Double = 30

    /// Hueco mínimo fiable: evita dividir un delta real por una ventana casi
    /// nula (pushes duplicados, cruces local↔daemon o refrescos inmediatos).
    public static func minimumGap(cadence: Double? = nil) -> Double {
        guard let cadence, cadence.isFinite, cadence > 0 else { return 0.2 }
        return max(0.2, cadence * 0.25)
    }

    /// Mismo criterio que `AppModel.isLive`: permite 2,5 ticks, nunca menos de 5 s,
    /// y exige el hueco mínimo fiable.
    public static func isValidGap(_ elapsed: Double, cadence: Double? = nil) -> Bool {
        guard elapsed.isFinite, elapsed >= minimumGap(cadence: cadence) else {
            return false
        }
        guard let cadence, cadence.isFinite, cadence > 0 else {
            return elapsed <= fallbackMaximumGap
        }
        return elapsed <= max(5.0, cadence * 2.5)
    }
}

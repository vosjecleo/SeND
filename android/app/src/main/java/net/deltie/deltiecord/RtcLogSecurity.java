package net.deltie.deltiecord;

import java.lang.reflect.Method;
import java.lang.reflect.Modifier;

/** Keep both WebRTC logging sinks silent without removing the plugin's logger. */
public final class RtcLogSecurity {
    private RtcLogSecurity() {}

    public static void silence() throws ReflectiveOperationException {
        silence(Class.forName("org.webrtc.Logging"),
                Class.forName("org.webrtc.Logging$Severity"));
    }

    static void silence(Class<?> logging, Class<?> severity)
            throws ReflectiveOperationException {
        Object none = severity.getField("LS_NONE").get(null);
        if (!(none instanceof Enum<?>) || ((Enum<?>) none).ordinal() != 4) {
            throw new IllegalStateException("Unexpected WebRTC logging severity");
        }
        // Pinned WebRTC's public wrapper rejects an installed Loggable. Call
        // the same native setter directly, leaving that logger and its NONE
        // threshold intact. Never ignore a failure or fall back to noisy logs.
        Method disable = logging.getDeclaredMethod(
                "nativeEnableLogToDebugOutput", int.class);
        if (!Modifier.isStatic(disable.getModifiers()) ||
                disable.getReturnType() != void.class) {
            throw new IllegalStateException("Unexpected WebRTC logging API");
        }
        disable.setAccessible(true);
        disable.invoke(null, ((Enum<?>) none).ordinal());
    }
}

package net.deltie.deltiecord;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.lang.reflect.Modifier;
import java.lang.reflect.Proxy;

/** Host-JVM regression checks. No device, microphone, media keys or JNI calls. */
public final class RtcLogSecurityTest {
    public enum Severity { LS_VERBOSE, LS_INFO, LS_WARNING, LS_ERROR, LS_NONE }

    public static final class WithLogger {
        static final Object installedLogger = new Object();
        static Object logger = installedLogger;
        static int debugLevel = -1;
        public static void enableLogToDebugOutput(Severity ignored) {
            throw new AssertionError("Public logging wrapper must not be used");
        }
        private static void nativeEnableLogToDebugOutput(int level) {
            debugLevel = level;
        }
    }

    public static final class MissingSetter {}

    public static final class FailedSetter {
        private static void nativeEnableLogToDebugOutput(int ignored) {
            throw new IllegalStateException("Simulated native failure");
        }
    }

    private static void check(boolean value, String message) {
        if (!value) throw new AssertionError(message);
    }

    public static void main(String[] args) throws Exception {
        RtcLogSecurity.silence(WithLogger.class, Severity.class);
        RtcLogSecurity.silence(WithLogger.class, Severity.class);
        check(WithLogger.debugLevel == 4, "Native debug output must be NONE");
        check(WithLogger.logger == WithLogger.installedLogger, "Keep the injected logger");
        try {
            RtcLogSecurity.silence(MissingSetter.class, Severity.class);
            throw new AssertionError("Missing APIs must fail closed");
        } catch (NoSuchMethodException expected) {}
        try {
            RtcLogSecurity.silence(FailedSetter.class, Severity.class);
            throw new AssertionError("Native errors must fail closed");
        } catch (InvocationTargetException expected) {
            check(expected.getCause() instanceof IllegalStateException,
                    "Preserve the native failure");
        }

        // Validate the exact AAR shipped by Flutter WebRTC. Reproduce the old
        // public guard before it could reach JNI; do not load Android native code.
        Class<?> logging = Class.forName("org.webrtc.Logging");
        Class<?> severity = Class.forName("org.webrtc.Logging$Severity");
        Class<?> loggable = Class.forName("org.webrtc.Loggable");
        Object none = severity.getField("LS_NONE").get(null);
        check(((Enum<?>) none).ordinal() == 4, "Review the pinned severity mapping");
        Method setter = logging.getDeclaredMethod("nativeEnableLogToDebugOutput", int.class);
        check(Modifier.isStatic(setter.getModifiers()) && Modifier.isNative(setter.getModifiers())
                && setter.getReturnType() == void.class, "Review the pinned JNI contract");
        Object sink = Proxy.newProxyInstance(loggable.getClassLoader(),
                new Class<?>[]{loggable}, (proxy, method, parameters) -> null);
        Method inject = logging.getDeclaredMethod("injectLoggable", loggable, severity);
        inject.setAccessible(true);
        inject.invoke(null, sink, none);
        try {
            logging.getMethod("enableLogToDebugOutput", severity).invoke(null, none);
            throw new AssertionError("Expected the old logging guard");
        } catch (InvocationTargetException expected) {
            check(expected.getCause() instanceof IllegalStateException,
                    "Expected the injected-logger guard, not a native call");
        }
        System.out.println("RTC logging regression passed: silent JNI setter, logger retained, fail-closed errors, pinned AAR contract");
    }
}

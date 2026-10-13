package net.deltie.deltiecord

import android.app.Activity
import android.view.View
import android.view.ViewGroup
import android.view.ViewTreeObserver
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsAnimationCompat
import androidx.core.view.WindowInsetsCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/** Observe IME geometry without replacing Flutter's insets or input handlers. */
class ComposerKeyboardBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : EventChannel.StreamHandler {
    private val channel = EventChannel(messenger, "net.deltie.deltiecord/keyboard_geometry")
    private val root = activity.window.decorView
    private val parent = root.findViewById<ViewGroup>(android.R.id.content)
    private val observer = View(activity).apply {
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        isFocusable = false
    }
    private var sink: EventChannel.EventSink? = null
    private var last: Map<String, Any?>? = null
    private var animating = false
    private var disposed = false
    private val layoutListener = ViewTreeObserver.OnGlobalLayoutListener { emit() }

    init {
        parent.addView(observer, ViewGroup.LayoutParams(0, 0))
        root.viewTreeObserver.addOnGlobalLayoutListener(layoutListener)
        ViewCompat.setWindowInsetsAnimationCallback(observer,
            object : WindowInsetsAnimationCompat.Callback(DISPATCH_MODE_CONTINUE_ON_SUBTREE) {
                override fun onPrepare(animation: WindowInsetsAnimationCompat) {
                    if (animation.typeMask and WindowInsetsCompat.Type.ime() != 0) {
                        animating = true
                        emit()
                    }
                }
                override fun onEnd(animation: WindowInsetsAnimationCompat) {
                    if (animation.typeMask and WindowInsetsCompat.Type.ime() != 0) {
                        animating = false
                        emit()
                    }
                }
                override fun onProgress(
                    insets: WindowInsetsCompat,
                    runningAnimations: MutableList<WindowInsetsAnimationCompat>,
                ): WindowInsetsCompat {
                    emit()
                    return insets
                }
            })
        channel.setStreamHandler(this)
    }

    fun snapshot(): Map<String, Any?> {
        val insets = ViewCompat.getRootWindowInsets(root)
        val focused = root.hasWindowFocus()
        return mapOf(
            "visible" to if (focused) insets?.isVisible(WindowInsetsCompat.Type.ime()) else null,
            "physicalBottom" to (insets?.getInsets(WindowInsetsCompat.Type.ime())?.bottom ?: 0),
            "focused" to focused,
            "animating" to animating,
        )
    }

    fun refresh(resetAnimation: Boolean = false) {
        if (disposed) return
        // FlutterActivity installs its content view after engine configuration.
        if (observer.parent == null) parent.addView(observer, ViewGroup.LayoutParams(0, 0))
        if (resetAnimation) {
            animating = false
            root.requestLayout()
        }
        ViewCompat.requestApplyInsets(root)
        root.postOnAnimation { if (!disposed) emit() }
    }

    private fun emit() {
        if (disposed || sink == null) return
        val next = snapshot()
        if (next == last) return
        last = next
        sink?.success(next)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        last = null
        refresh()
    }

    override fun onCancel(arguments: Any?) { sink = null }

    fun dispose() {
        disposed = true
        sink = null
        channel.setStreamHandler(null)
        if (root.viewTreeObserver.isAlive) root.viewTreeObserver.removeOnGlobalLayoutListener(layoutListener)
        ViewCompat.setWindowInsetsAnimationCallback(observer, null)
        parent.removeView(observer)
    }
}

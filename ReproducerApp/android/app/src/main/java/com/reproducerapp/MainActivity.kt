package com.reproducerapp

import android.os.Bundle
import android.util.Log
import android.view.View
import com.facebook.react.ReactActivity
import com.facebook.react.ReactActivityDelegate
import com.facebook.react.defaults.DefaultReactActivityDelegate
import com.facebook.react.internal.featureflags.ReactNativeFeatureFlags
import com.facebook.react.uimanager.util.ReactFindViewUtil

class MainActivity : ReactActivity() {

  /**
   * Returns the name of the main component registered from JavaScript. This is used to schedule
   * rendering of the component.
   */
  override fun getMainComponentName(): String = "ReproducerApp"

  /** Returns the instance of the [ReactActivityDelegate]. */
  override fun createReactActivityDelegate(): ReactActivityDelegate =
      DefaultReactActivityDelegate(this, mainComponentName)

  // Logs which Android view instance each subject is drawn by, and its nextFocusLeftId once its
  // props are applied.
  private val subjectListener =
      ReactFindViewUtil.OnMultipleViewsFoundListener { view: View, nativeId: String ->
        view.post {
          Log.i(
              TAG,
              "$nativeId: view instance ${System.identityHashCode(view)}, id ${view.id}, " +
                  "nextFocusLeftId ${view.nextFocusLeftId}",
          )
        }
      }

  override fun onCreate(savedInstanceState: Bundle?) {
    Log.i(TAG, "enableViewRecycling ${ReactNativeFeatureFlags.enableViewRecycling()}")
    ReactFindViewUtil.addViewsListener(subjectListener, setOf("subject-old", "subject-new"))
    super.onCreate(savedInstanceState)
  }

  override fun onDestroy() {
    ReactFindViewUtil.removeViewsListener(subjectListener)
    super.onDestroy()
  }

  private companion object {
    const val TAG = "RecycledFocusReproducer"
  }
}

package com.shiva2232.orbitx

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle

class VpnPermissionActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val prepare = VpnService.prepare(this)
        if (prepare != null) {
            startActivityForResult(prepare, 1001)
        } else {
            // already prepared
            setResult(Activity.RESULT_OK, intent)
            finish()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        setResult(resultCode, intent)
        finish()
    }
}

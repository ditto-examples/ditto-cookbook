package com.example.fieldservice.data

import com.ditto.kotlin.*

/** Owns the subscriptions of the site that the technician is working at. */
class WorkOrderSync(private val ditto: Ditto) {
    private var subscription: DittoSyncSubscription? = null
    private var siteId: String? = null

    /** Called after every Ditto.open() and whenever the technician changes site. */
    fun enterSite(siteId: String) {
        if (siteId == this.siteId && subscription?.isClosed == false) return
        leaveSite()
        this.siteId = siteId
        subscription = ditto.sync.registerSubscription(
            "SELECT * FROM workOrders WHERE siteId = :siteId",
            mapOf("siteId" to siteId),
        )
    }

    fun leaveSite() {
        subscription?.close()
        subscription = null
        siteId = null
    }
}

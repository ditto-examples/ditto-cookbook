package com.example.fieldservice.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.ditto.kotlin.*
import com.example.fieldservice.data.WorkOrder
import com.example.fieldservice.data.WorkOrderRepository
import com.example.fieldservice.data.workOrderFromValue
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class WorkOrdersViewModel(
    ditto: Ditto,
    private val repository: WorkOrderRepository,
    siteId: String,
) : ViewModel() {

    /** The site's work orders, newest first; the observer ends with viewModelScope. */
    val workOrders: StateFlow<List<WorkOrder>> = ditto.store
        .observe(
            "SELECT * FROM workOrders WHERE siteId = :siteId ORDER BY createdAt DESC, _id",
            mapOf("siteId" to siteId),
        ) { result -> result.items.map { workOrderFromValue(it.value) } }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    fun addPart(orderId: String, partNumber: String, quantity: Int) {
        viewModelScope.launch { repository.addPart(orderId, partNumber, quantity) }
    }

    fun reschedule(orderId: String, scheduledFor: String) {
        viewModelScope.launch { repository.reschedule(orderId, scheduledFor) }
    }
}

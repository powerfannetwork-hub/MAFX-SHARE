package com.mafx.share

import java.net.Inet4Address
import java.net.NetworkInterface

object NetworkAddress {

    fun getLocalIPv4Address(): String? {
        return try {
            val interfaces = NetworkInterface.getNetworkInterfaces()
                ?: return null

            val addresses = mutableListOf<String>()

            while (interfaces.hasMoreElements()) {
                val networkInterface = interfaces.nextElement()

                if (!networkInterface.isUp ||
                    networkInterface.isLoopback
                ) {
                    continue
                }

                val interfaceAddresses =
                    networkInterface.inetAddresses

                while (interfaceAddresses.hasMoreElements()) {
                    val address = interfaceAddresses.nextElement()

                    if (address is Inet4Address &&
                        !address.isLoopbackAddress &&
                        !address.isLinkLocalAddress
                    ) {
                        addresses.add(address.hostAddress ?: continue)
                    }
                }
            }

            addresses.firstOrNull {
                it.startsWith("192.168.") ||
                it.startsWith("10.") ||
                it.startsWith("172.")
            } ?: addresses.firstOrNull()

        } catch (_: Exception) {
            null
        }
    }
}

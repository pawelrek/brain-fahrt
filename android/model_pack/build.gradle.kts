plugins {
    id("com.android.asset-pack")
}

assetPack {
    packName = "model_pack"
    dynamicDelivery {
        deliveryType = "install-time"
    }
}

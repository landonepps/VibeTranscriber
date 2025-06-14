import Foundation

func getResource(_ forResource: String, _ ofType: String) -> String {
    let path = Bundle.main.path(forResource: forResource, ofType: ofType)
    precondition(
        path != nil,
        "\(forResource).\(ofType) does not exist!\n" + "Remember to change \n"
        + "  Build Phases -> Copy Bundle Resources\n" + "to add it!"
    )
    return path!
}

func getNemoParakeetEn() -> SherpaOnnxOfflineModelConfig {
    let encoder = getResource("encoder.int8", "onnx")
    let decoder = getResource("decoder.int8", "onnx")
    let joiner = getResource("joiner.int8", "onnx")
    let tokens = getResource("tokens", "txt")

    return sherpaOnnxOfflineModelConfig(
        tokens: tokens,
        transducer: sherpaOnnxOfflineTransducerModelConfig(
            encoder: encoder,
            decoder: decoder,
            joiner: joiner
        ),
        numThreads: 8,
        provider: "cpu", // want to try coreml but get memory error
        modelType: "nemo_transducer"
    )
}

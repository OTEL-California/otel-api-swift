/*
 * Copyright The OpenTelemetry Authors
 * SPDX-License-Identifier: Apache-2.0
 */

import Foundation
import OpenTelemetrySdk

enum LogLevel: Int, Codable {
  case debug
  case info
  case notice
  case warn
  case error
  case critical
}

class LogsExporter {
  let logsDirectory = "com.otel.datadog.logs/v1"
  let configuration: ExporterConfiguration
  let logsStorage: FeatureStorage
  let logsUpload: FeatureUpload

  init(config: ExporterConfiguration) throws {
    configuration = config

    let filesOrchestrator = try FilesOrchestrator(directory: Directory(withSubdirectoryPath: logsDirectory),
                                                  performance: configuration.performancePreset,
                                                  dateProvider: SystemDateProvider())

    let dataFormat = DataFormat(prefix: "[", suffix: "]", separator: ",")

    let logsFileWriter = FileWriter(dataFormat: dataFormat,
                                    orchestrator: filesOrchestrator)

    let logsFileReader = FileReader(dataFormat: dataFormat,
                                    orchestrator: filesOrchestrator)

    logsStorage = FeatureStorage(writer: logsFileWriter, reader: logsFileReader)

    let requestBuilder = RequestBuilder(url: configuration.endpoint.logsURL,
                                        queryItems: [
                                          .ddsource(source: configuration.source)
                                        ],
                                        headers: [
                                          .contentTypeHeader(contentType: .applicationJSON),
                                          .userAgentHeader(appName: configuration.applicationName,
                                                           appVersion: configuration.version,
                                                           device: Device.current),
                                          .ddAPIKeyHeader(apiKey: configuration.apiKey),
                                          .ddEVPOriginHeader(source: configuration.source),
                                          .ddEVPOriginVersionHeader(version: configuration.version),
                                          .ddRequestIDHeader()
                                        ] + (configuration.payloadCompression ? [RequestBuilder.HTTPHeader.contentEncodingHeader(contentEncoding: .deflate)] : []))

    logsUpload = FeatureUpload(featureName: "logsUpload",
                               storage: logsStorage,
                               requestBuilder: requestBuilder,
                               performance: configuration.performancePreset,
                               uploadCondition: configuration.uploadCondition)
  }

  func exportLogs(fromSpan span: SpanData) {
    span.events.forEach {
      let log = DDLog(event: $0, span: span, configuration: configuration)
      if configuration.performancePreset.synchronousWrite {
        logsStorage.writer.writeSync(value: log)
      } else {
        logsStorage.writer.write(value: log)
      }
    }
  }
}

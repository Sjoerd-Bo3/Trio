import Foundation

extension Home.StateModel {
    func yAxisChartData(glucoseValues: [GlucoseStored]) {
        // Capture the forecast values from `preprocessedData` on the main thread
        Task { @MainActor in
            let forecastValues = self.preprocessedData.map { Decimal($0.forecastValue.value) }

            // Perform the glucose processing on the background context
            glucoseFetchContext.perform {
                let glucoseMapped = glucoseValues.map { Decimal($0.glucose) }

                // Calculate min and max values for glucose and forecast
                let minGlucose = glucoseMapped.min()
                let maxGlucose = glucoseMapped.max()
                let minForecast = forecastValues.min()
                let maxForecast = forecastValues.max()

                // Ensure all values exist, otherwise set default values
                guard let minGlucose = minGlucose, let maxGlucose = maxGlucose else {
                    Task {
                        await self.updateChartBounds(minValue: 39, maxValue: 300)
                    }
                    return
                }

                // Adjust max forecast to be no more than 100 over max glucose
                let adjustedMaxForecast = min(maxForecast ?? maxGlucose + 100, maxGlucose + 100)
                let minOverall = min(minGlucose, minForecast ?? minGlucose)
                let maxOverall = max(maxGlucose, adjustedMaxForecast)

                // Update the chart bounds on the main thread
                Task {
                    await self.updateChartBounds(minValue: minOverall - 50, maxValue: maxOverall + 80)
                }
            }
        }
    }

    @MainActor private func updateChartBounds(minValue: Decimal, maxValue: Decimal) async {
        minYAxisValue = minValue
        maxYAxisValue = maxValue
    }

    func yAxisChartDataCobChart(determinations: [[String: Any]]) {
        determinationFetchContext.perform {
            // Map the COB values from the dictionary results
            let cobMapped = determinations.compactMap { entry in
                // First cast to Int16, then convert to Decimal
                if let cobValue = entry["cob"] as? Int16 {
                    return Decimal(cobValue)
                }
                return nil
            }
            let maxCob = cobMapped.max()

            // Ensure the result exists or set default values
            if let maxCob = maxCob {
                let calculatedMax = maxCob == 0 ? 20 : maxCob + 20
                Task {
                    await self.updateCobChartBounds(minValue: 0, maxValue: calculatedMax)
                }
            } else {
                Task {
                    await self.updateCobChartBounds(minValue: 0, maxValue: 20)
                }
            }
        }
    }

    @MainActor private func updateCobChartBounds(minValue: Decimal, maxValue: Decimal) {
        minValueCobChart = minValue
        maxValueCobChart = maxValue
    }

    func yAxisChartDataIobChart(determinations: [[String: Any]]) {
        determinationFetchContext.perform {
            // Map the IOB values from the fetched dictionaries
            let iobMapped = determinations.compactMap { ($0["iob"] as? NSDecimalNumber)?.decimalValue }
            let minIob = iobMapped.min()
            let maxIob = iobMapped.max()

            // Ensure min and max IOB values exist, or set defaults
            if let minIob = minIob, let maxIob = maxIob {
                let adjustedMin = minIob < 0 ? minIob - 2 : 0
                Task {
                    await self.updateIobChartBounds(minValue: adjustedMin, maxValue: maxIob + 2)
                }
            } else {
                Task {
                    await self.updateIobChartBounds(minValue: 0, maxValue: 5)
                }
            }
        }
    }

    @MainActor private func updateIobChartBounds(minValue: Decimal, maxValue: Decimal) async {
        minValueIobChart = minValue
        maxValueIobChart = maxValue
    }
}

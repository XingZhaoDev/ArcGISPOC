//
//  ViewController.swift
//  ArcGISPOC
//
//  Created by XING ZHAO on 2025-04-02.
//

import UIKit
import ArcGIS

class ViewController: UIViewController {
    let graphicsOverlay = AGSGraphicsOverlay()
    let sketchEditor = AGSSketchEditor()
    let creationModes: KeyValuePairs = [
        "Arrow": AGSSketchCreationMode.arrow,
        "Ellipse": .ellipse,
        "Lasso": .freehandPolygon,
        "FreehandPolyline": .freehandPolyline,
        "Multipoint": .multipoint,
        "Point": .point,
        "Polygon": .polygon,
        "Polyline": .polyline,
        "Rectangle": .rectangle,
        "Triangle": .triangle
    ]
    var barItemObserver: NSObjectProtocol!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        view.addSubview(mapView)
        mapView.setViewpoint(AGSViewpoint(latitude: 56.075844, longitude: -2.681572, scale: 288895.277144))
        
        // Set the spatial reference for the sketch editor to match the points
        //sketchEditor.tool.spatialReference = AGSSpatialReference.wgs84()
        
        // Add the graphics overlay to the map view.
        mapView.graphicsOverlays.add(graphicsOverlay)

        // Check and load saved points or add custom points
        if hasSavedPoints() {
            loadSavedPoints()
        } else {
            addCustomPoints()
        }
        
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.widthAnchor.constraint(equalToConstant: 150),
            statusLabel.heightAnchor.constraint(equalToConstant: 30),
        ])
        
        // Add notification observer
        barItemObserver = NotificationCenter.default.addObserver(forName: .AGSSketchEditorGeometryDidChange, object: sketchEditor, queue: nil, using: { [unowned self] _ in
            self.handleSketchEditorChange()
        })
        
        setupBottomBar()
        
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    private func handleSketchEditorChange() {
        // Check if the drawing is complete (you can add more validation if needed)
        if let geometry = sketchEditor.geometry, !geometry.isEmpty {
            print("Drawing completed or updated.")
            selectPointsInsideShape()
        }
    }
    
    // Make sure to remove the observer when appropriate, like in deinit
    deinit {
        if let observer = barItemObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    lazy var statusLabel: UILabel = {
        let label = UILabel(frame: .zero)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .red
        label.text = "Unselected"
        return label
    }()
    
    lazy var mapView: AGSMapView = {
        let mapView = AGSMapView(frame: .zero)
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapView.map = AGSMap(basemapStyle: .arcGISChartedTerritory)
        mapView.sketchEditor = sketchEditor
        return mapView
    }()

    private func setupBottomBar() {
        let bottomBar = UIStackView()
        bottomBar.axis = .horizontal
        bottomBar.distribution = .fillEqually
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        
        // Create a background view for the bottom bar
        let bottomBarBackground = UIView()
        bottomBarBackground.translatesAutoresizingMaskIntoConstraints = false
        bottomBarBackground.backgroundColor = .lightGray // CHANGE: Set your desired color here
        
        // Add the background view and then the stack view to it
        view.addSubview(bottomBarBackground)
        bottomBarBackground.addSubview(bottomBar)
        
        // Constraints for background view
        NSLayoutConstraint.activate([
            bottomBarBackground.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            bottomBarBackground.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            bottomBarBackground.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -50),
            bottomBarBackground.heightAnchor.constraint(equalToConstant: 150)
        ])
        
        // Constraints for stack view within the background
        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: bottomBarBackground.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: bottomBarBackground.trailingAnchor),
            bottomBar.topAnchor.constraint(equalTo: bottomBarBackground.topAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: bottomBarBackground.bottomAnchor)
        ])
        
        // Create buttons
        let rectangleButton = createButton(title: "Rectangle")
        let lassoButton = createButton(title: "Lasso")
        let ovalButton = createButton(title: "Ellipse")
        let pointsButton = createButton(title: "Multipoint")
        
        // Add buttons to stack view
        bottomBar.addArrangedSubview(rectangleButton)
        bottomBar.addArrangedSubview(lassoButton)
        bottomBar.addArrangedSubview(ovalButton)
        bottomBar.addArrangedSubview(pointsButton)
        
        // Update mapView constraints
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.bottomAnchor.constraint(equalTo: bottomBarBackground.topAnchor)
        ])
    }

    private func createButton(title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.addTarget(self, action: #selector(bottomBarButtonTapped(_:)), for: .touchUpInside)
        return button
    }

    // ADD: Function to handle button taps
    @objc private func bottomBarButtonTapped(_ sender: UIButton) {
        guard let title = sender.titleLabel?.text else { return }
        print("\(title) button tapped")
        
        for (name, mode) in creationModes {
            if name == title {
                statusLabel.text = "\(title)"
                sketchEditor.start(with: nil, creationMode: mode)
                break
            }
        }
    }
    
    private func hasSavedPoints() -> Bool {
        return UserDefaults.standard.data(forKey: "savedPoints") != nil
    }
    
    func addCustomPoints() {
        // CHANGE: Use a local image file for the apple icon
        if let appleImage = UIImage(named: "applelogo") { // Ensure "applelogo" is in your asset catalog
            let markerSymbol = AGSPictureMarkerSymbol(image: appleImage)
            markerSymbol.width = 20
            markerSymbol.height = 20
            
            // Example initial point
            let centerPoint = AGSPoint(x: -2.712642647560347, y: 56.062812566811544, spatialReference: .wgs84())
            
            // Add the initial example point
            let initialGraphic = AGSGraphic(geometry: centerPoint, symbol: markerSymbol, attributes: ["name": "Center Point"])
            graphicsOverlay.graphics.add(initialGraphic)
            
            // ADD: Generate 48 more random points around the initial point and add them to the overlay
            for i in 0..<48 {
                let randomX = centerPoint.x + Double.random(in: -0.01...0.01)
                let randomY = centerPoint.y + Double.random(in: -0.01...0.01)
                let randomPoint = AGSPoint(x: randomX, y: randomY, spatialReference: .wgs84())
                let graphic = AGSGraphic(geometry: randomPoint, symbol: markerSymbol, attributes: ["name": "Point \(i + 1)"])
                graphicsOverlay.graphics.add(graphic)
            }
            
            // Save all the points
            saveGraphics(graphics: Array(_immutableCocoaArray: graphicsOverlay.graphics))
        } else {
            print("Image 'applelogo' not found in assets.")
        }
    }

    func saveGraphics(graphics: [AGSGraphic]) {
        var pointsArray: [[String: Any]] = []
        
        for graphic in graphics {
            if let geometry = graphic.geometry as? AGSPoint {
                let pointDict: [String: Any] = [
                    "latitude": geometry.y,
                    "longitude": geometry.x,
                    "attributes": graphic.attributes
                ]
                pointsArray.append(pointDict)
            }
        }
        
        // Persist jsonData to UserDefaults
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: pointsArray, options: .prettyPrinted)
            UserDefaults.standard.setValue(jsonData, forKey: "savedPoints")
            print("Saved JSON: \(String(data: jsonData, encoding: .utf8) ?? "")")
        } catch {
            print("Failed to save graphics: \(error)")
        }
    }

    func loadSavedPoints() {
        guard let jsonData = UserDefaults.standard.data(forKey: "savedPoints") else { return }
        
        do {
            if let pointsArray = try JSONSerialization.jsonObject(with: jsonData, options: []) as? [[String: Any]] {
                // CHANGE: Use an apple icon for loaded points
                if let appleImage = UIImage(named: "applelogo") { // Ensure "applelogo" is in your asset catalog
                    let markerSymbol = AGSPictureMarkerSymbol(image: appleImage)
                    markerSymbol.width = 20
                    markerSymbol.height = 20
                    
                    for pointDict in pointsArray {
                        if let latitude = pointDict["latitude"] as? Double,
                           let longitude = pointDict["longitude"] as? Double {
                            let point = AGSPoint(x: longitude, y: latitude, spatialReference: .wgs84())
                            let graphic = AGSGraphic(geometry: point, symbol: markerSymbol, attributes: pointDict["attributes"] as? [String: Any])
                            graphicsOverlay.graphics.add(graphic)
                        }
                    }
                } else {
                    print("Image 'applelogo' not found in assets.")
                }
            }
        } catch {
            print("Failed to load saved points: \(error)")
        }
    }
    
    func selectPointsInsideShape() {
        guard let sketchGeometry = sketchEditor.geometry else { return }
        
        for graphic in graphicsOverlay.graphics as! [AGSGraphic] { // Ensure correct casting
            if let pointGeometry = graphic.geometry as? AGSPoint {
                // Ensure both geometries are in the same spatial reference
                if pointGeometry.spatialReference != sketchGeometry.spatialReference {
                    print("Spatial reference mismatch: Point-\(pointGeometry.spatialReference), Shape-\(sketchGeometry.spatialReference)")
                    continue
                }
                
                if AGSGeometryEngine.geometry(pointGeometry, within: sketchGeometry) {
                    graphic.isSelected = true
                    print("Point inside shape: \(graphic.attributes)")
                } else {
                    graphic.isSelected = false
                    print("Point outside shape: \(graphic.attributes)")
                }
            }
        }
    }
}

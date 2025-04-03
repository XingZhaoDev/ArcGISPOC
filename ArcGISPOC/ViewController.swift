//
//  ViewController.swift
//  ArcGISPOC
//
//  Created by XING ZHAO on 2025-04-02.
//

import UIKit
import ArcGIS

class ViewController: UIViewController {
    let pointsOverlay = AGSGraphicsOverlay() // For points
    let shapesOverlay = AGSGraphicsOverlay() // For shapes
    let sketchEditor = AGSSketchEditor()
    var barItemObserver: NSObjectProtocol!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.addSubview(mapView)
        mapView.setViewpoint(AGSViewpoint(latitude: 56.075844, longitude: -2.681572, scale: 288895.277144))
        
        // Add both graphics overlays to the map view
        mapView.graphicsOverlays.addObjects(from: [pointsOverlay, shapesOverlay])

        // Load or add points
        if hasSavedPoints() {
        //    loadSavedPoints()
        } else {
        //    addCustomPoints()
        }
        
        // Load saved shapes
        addCustomPoints()
        
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
        if let geometry = sketchEditor.geometry, !geometry.isEmpty {
            print("Drawing completed or updated.")
            selectPointsInsideShape()
            
            // Create a graphic from the sketch and add it to the shapes overlay
            let fillSymbol = AGSSimpleFillSymbol(style: .solid, color: .blue.withAlphaComponent(0.2), outline: AGSSimpleLineSymbol(style: .solid, color: .blue, width: 2))
            let graphic = AGSGraphic(geometry: geometry, symbol: fillSymbol)
            shapesOverlay.graphics.add(graphic)
        }
    }

    func selectPointsInsideShape() {
        guard let sketchGeometry = sketchEditor.geometry else { return }
        
        // Reset all selections first
        for graphic in pointsOverlay.graphics as! [AGSGraphic] {
            graphic.isSelected = false
        }
        
        var selectedIds: [Int] = []
        
        for graphic in pointsOverlay.graphics as! [AGSGraphic] {
            if let pointGeometry = graphic.geometry as? AGSPoint {
                // Project point to sketch's spatial reference if needed
                if pointGeometry.spatialReference != sketchGeometry.spatialReference {
                    guard let projectedPoint = AGSGeometryEngine.projectGeometry(pointGeometry, to: sketchGeometry.spatialReference!) else { continue }
                    
                    if AGSGeometryEngine.geometry(projectedPoint, within: sketchGeometry) {
                        graphic.isSelected = true
                        if let id = graphic.attributes["id"] as? Int {
                            selectedIds.append(id)
                        }
                    }
                } else {
                    if AGSGeometryEngine.geometry(pointGeometry, within: sketchGeometry) {
                        graphic.isSelected = true
                        if let id = graphic.attributes["id"] as? Int {
                            selectedIds.append(id)
                        }
                    }
                }
            }
        }
        
        // Sort and print selected IDs
        selectedIds.sort()
        print("Selected point IDs: \(selectedIds)")
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
        bottomBarBackground.backgroundColor = .lightGray
        
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

    @objc private func bottomBarButtonTapped(_ sender: UIButton) {
        guard let title = sender.titleLabel?.text else { return }
        print("\(title) button tapped")
        
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
        if let appleImage = UIImage(named: "applelogo") {
            let markerSymbol = AGSPictureMarkerSymbol(image: appleImage)
            markerSymbol.width = 20
            markerSymbol.height = 20
            
            // Example initial point
            let centerPoint = AGSPoint(x: -2.712642647560347, y: 56.062812566811544, spatialReference: .wgs84())
            
            // Add the initial example point with id 0
            let initialGraphic = AGSGraphic(geometry: centerPoint, symbol: markerSymbol, attributes: ["id": 0, "name": "Center Point"])
            pointsOverlay.graphics.add(initialGraphic)
            
            // Generate 48 more random points around the initial point and add them to the overlay
            for i in 1..<49 { // Start from 1 since center point is 0
                let randomX = centerPoint.x + Double.random(in: -0.01...0.01)
                let randomY = centerPoint.y + Double.random(in: -0.01...0.01)
                let randomPoint = AGSPoint(x: randomX, y: randomY, spatialReference: .wgs84())
                let graphic = AGSGraphic(geometry: randomPoint, symbol: markerSymbol, attributes: ["id": i, "name": "Point \(i)"])
                pointsOverlay.graphics.add(graphic)
            }
            
            saveGraphics(graphics: Array(_immutableCocoaArray: pointsOverlay.graphics))
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
                if let appleImage = UIImage(named: "applelogo") {
                    let markerSymbol = AGSPictureMarkerSymbol(image: appleImage)
                    markerSymbol.width = 20
                    markerSymbol.height = 20
                    
                    for pointDict in pointsArray {
                        if let latitude = pointDict["latitude"] as? Double,
                           let longitude = pointDict["longitude"] as? Double {
                            let point = AGSPoint(x: longitude, y: latitude, spatialReference: .wgs84())
                            let graphic = AGSGraphic(geometry: point, symbol: markerSymbol, attributes: pointDict["attributes"] as? [String: Any])
                            pointsOverlay.graphics.add(graphic)
                        }
                    }
                }
            }
        } catch {
            print("Failed to load saved points: \(error)")
        }
    }
    
    func loadSavedShapes() {
        // Add implementation to load saved shapes
    }
    
    deinit {
        if let observer = barItemObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

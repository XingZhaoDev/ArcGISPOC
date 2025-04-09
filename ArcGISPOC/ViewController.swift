//
//  ViewController.swift
//  ArcGISPOC
//
//  Created by XING ZHAO on 2025-04-02.
//

import UIKit
import ArcGIS

class ViewController: UIViewController, AGSGeoViewTouchDelegate {
    let pointsOverlay = AGSGraphicsOverlay() // For points
    let shapesOverlay = AGSGraphicsOverlay() // For shapes
    let sketchEditor = AGSSketchEditor()
    var barItemObserver: NSObjectProtocol!
    // ADD: Track last added graphic for undo
    private var lastAddedGraphic: AGSGraphic?
    // ADD: Track currently selected button
    private var selectedButton: UIButton?
    // ADD: Track selected points across shapes
    private var selectedPointIds: Set<Int> = []
    private var selectedGeometries: [AGSGeometry] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // ADD: Set view background color
        view.backgroundColor = .systemBackground
        
        // Configure navigation bar appearance
        if #available(iOS 13.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithDefaultBackground()
            navigationController?.navigationBar.standardAppearance = appearance
            navigationController?.navigationBar.scrollEdgeAppearance = appearance
            navigationController?.navigationBar.compactAppearance = appearance
        }
        navigationController?.setNavigationBarHidden(false, animated: false)
        navigationItem.title = "Map Selection"  // Optional: add a title
        
        // Setup navigation bar buttons
        setupNavigationBar()
        
        view.addSubview(mapView)
        mapView.backgroundColor = .systemBackground
        
        // CHANGE: Set initial viewpoint to Vancouver, BC
        mapView.setViewpoint(AGSViewpoint(
            center: AGSPoint(x: -123.1207, y: 49.2827, spatialReference: .wgs84()), // Vancouver coordinates
            scale: 25000  // City level zoom
            // 25000 neighbourhood level
        ))
        
        // Add both graphics overlays to the map view
        mapView.graphicsOverlays.addObjects(from: [pointsOverlay, shapesOverlay])
        
        // Set the touch delegate
        mapView.touchDelegate = self
        
        // Load or add points
        if hasSavedPoints() {
           // loadSavedPoints()
        } else {
          //  addCustomPoints()
        }
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
            if geometry is AGSPolyline {
                // For freehand polyline
                selectPointsNearPolyline(geometry as! AGSPolyline)
            } else {
                // For other shapes (polygons, rectangles, etc.)
                selectPointsInsideShape(with: geometry)
            }
            
            // Clear the sketch editor and shapes overlay after selection is complete
            DispatchQueue.main.async {
                self.sketchEditor.clearGeometry()
                self.shapesOverlay.graphics.removeAllObjects()
            }
        }
    }

    private func selectPointsInsideShape(with geometry: AGSGeometry) {
        // Add new geometry to the list
        selectedGeometries.append(geometry)
        
        // Reset all selections first
        for graphic in pointsOverlay.graphics as! [AGSGraphic] {
            graphic.isSelected = false
        }
        
        var currentlySelectedIds: Set<Int> = []
        
        // Check points against all geometries
        for graphic in pointsOverlay.graphics as! [AGSGraphic] {
            if let pointGeometry = graphic.geometry as? AGSPoint {
                for selectGeometry in selectedGeometries {
                    if pointGeometry.spatialReference != selectGeometry.spatialReference {
                        guard let projectedPoint = AGSGeometryEngine.projectGeometry(pointGeometry, to: selectGeometry.spatialReference!) else { continue }
                        
                        if AGSGeometryEngine.geometry(projectedPoint, within: selectGeometry) {
                            graphic.isSelected = true
                            if let id = graphic.attributes["id"] as? Int {
                                currentlySelectedIds.insert(id)
                            }
                            break  // Break inner loop once point is selected
                        }
                    } else {
                        if AGSGeometryEngine.geometry(pointGeometry, within: selectGeometry) {
                            graphic.isSelected = true
                            if let id = graphic.attributes["id"] as? Int {
                                currentlySelectedIds.insert(id)
                            }
                            break  // Break inner loop once point is selected
                        }
                    }
                }
            }
        }
        
        // Update selected IDs
        selectedPointIds = currentlySelectedIds
        
        // Sort and print selected IDs
        let sortedIds = Array(selectedPointIds).sorted()
        print("Total selected points: \(selectedPointIds.count)")
        print("Selected point IDs: \(sortedIds)")
        
        // Update status label
        DispatchQueue.main.async {
            self.statusLabel.text = "Selected: \(self.selectedPointIds.count)"
        }
    }

    private func selectPointsNearPolyline(_ polyline: AGSPolyline) {
        // Add buffered geometry to the list
        if let bufferedGeometry = AGSGeometryEngine.bufferGeometry(polyline, byDistance: 1.5) {
            selectedGeometries.append(bufferedGeometry)
        }
        
        // Reset all selections first
        for graphic in pointsOverlay.graphics as! [AGSGraphic] {
            graphic.isSelected = false
        }
        
        var currentlySelectedIds: Set<Int> = []
        
        // Check points against all geometries
        for graphic in pointsOverlay.graphics as! [AGSGraphic] {
            if let pointGeometry = graphic.geometry as? AGSPoint {
                for selectGeometry in selectedGeometries {
                    if pointGeometry.spatialReference != selectGeometry.spatialReference {
                        guard let projectedPoint = AGSGeometryEngine.projectGeometry(pointGeometry, to: selectGeometry.spatialReference!) else { continue }
                        
                        if AGSGeometryEngine.geometry(projectedPoint, within: selectGeometry) {
                            graphic.isSelected = true
                            if let id = graphic.attributes["id"] as? Int {
                                currentlySelectedIds.insert(id)
                            }
                            break  // Break inner loop once point is selected
                        }
                    } else {
                        if AGSGeometryEngine.geometry(pointGeometry, within: selectGeometry) {
                            graphic.isSelected = true
                            if let id = graphic.attributes["id"] as? Int {
                                currentlySelectedIds.insert(id)
                            }
                            break  // Break inner loop once point is selected
                        }
                    }
                }
            }
        }
        
        // Update selected IDs
        selectedPointIds = currentlySelectedIds
        
        // Sort and print selected IDs
        let sortedIds = Array(selectedPointIds).sorted()
        print("Total selected points: \(selectedPointIds.count)")
        print("Selected point IDs: \(sortedIds)")
        
        // Update status label
        DispatchQueue.main.async {
            self.statusLabel.text = "Selected: \(self.selectedPointIds.count)"
        }
    }
    
    // CHANGE: Update handleUndo to clear selected geometries
    private func handleUndo() {
        // Remove the last graphic from shapes overlay
        if let lastGraphic = shapesOverlay.graphics.lastObject as? AGSGraphic {
            shapesOverlay.graphics.remove(lastGraphic)
            
            // Remove last geometry from selectedGeometries
            if !selectedGeometries.isEmpty {
                selectedGeometries.removeLast()
            }
            
            // Reset selection when shape is removed
            for graphic in pointsOverlay.graphics as! [AGSGraphic] {
                graphic.isSelected = false
            }
            
            // Reselect points based on remaining geometries
            if let lastGeometry = selectedGeometries.last {
                selectPointsInsideShape(with: lastGeometry)
            } else {
                selectedPointIds.removeAll()
            }
            
            // Clear the sketch editor
            sketchEditor.stop()
            sketchEditor.clearGeometry()
            
            // Clear button selection
            selectedButton?.configuration?.background.backgroundColor = .clear
            selectedButton = nil
            
            // Update status label for empty selection
            if selectedGeometries.isEmpty {
                statusLabel.text = "Unselected"
            }
        }
    }
    
    // ADD: Touch delegate method
    func geoView(_ geoView: AGSGeoView, didTapAtScreenPoint screenPoint: CGPoint, mapPoint: AGSPoint) {
        // Get graphics near the tap location
        mapView.identify(pointsOverlay, screenPoint: screenPoint, tolerance: 12, returnPopupsOnly: false) { [weak self] result in
            guard let self = self,
                  !result.graphics.isEmpty else { return }
            
            // Get the first graphic we tapped on
            if let graphic = result.graphics.first {
                // Toggle selection state
                graphic.isSelected = !graphic.isSelected
                
                // Update selectedPointIds set
                if let id = graphic.attributes["id"] as? Int {
                    if graphic.isSelected {
                        self.selectedPointIds.insert(id)
                    } else {
                        self.selectedPointIds.remove(id)
                    }
                }
                
                // Update status label
                DispatchQueue.main.async {
                    self.statusLabel.text = "Selected: \(self.selectedPointIds.count)"
                }
                
                // Print current selection
                let sortedIds = Array(self.selectedPointIds).sorted()
                print("Total selected points: \(self.selectedPointIds.count)")
                print("Selected point IDs: \(sortedIds)")
            }
        }
    }
    
    // CHANGE: Update setupNavigationBar and add removeAllButtonTapped
    private func setupNavigationBar() {
        let selectAllButton = UIBarButtonItem(image: UIImage(systemName: "checkmark.circle"),
                                            style: .plain,
                                            target: self,
                                            action: #selector(selectAllButtonTapped))
        
        let removeAllButton = UIBarButtonItem(image: UIImage(systemName: "xmark.circle"),
                                            style: .plain,
                                            target: self,
                                            action: #selector(removeAllButtonTapped))
        
        navigationItem.rightBarButtonItems = [selectAllButton, removeAllButton]
    }

    // ADD: Remove all functionality
    @objc private func removeAllButtonTapped() {
        selectedPointIds.removeAll()
        selectedGeometries.removeAll()
        
        // Deselect all points
        for graphic in pointsOverlay.graphics as! [AGSGraphic] {
            graphic.isSelected = false
        }
        
        // Update status label
        statusLabel.text = "Unselected"
        
        // Clear any active sketch
        sketchEditor.stop()
        sketchEditor.clearGeometry()
        
        // Clear shape overlays
        shapesOverlay.graphics.removeAllObjects()
        
        // Clear button selection
        selectedButton?.configuration?.background.backgroundColor = .clear
        selectedButton = nil
        
        print("All points deselected")
    }

    // ADD: Select all functionality
    @objc private func selectAllButtonTapped() {
        selectedPointIds.removeAll()
        selectedGeometries.removeAll()
        
        // Select all points
        for graphic in pointsOverlay.graphics as! [AGSGraphic] {
            graphic.isSelected = true
            if let id = graphic.attributes["id"] as? Int {
                selectedPointIds.insert(id)
            }
        }
        
        // Sort and print selected IDs
        let sortedIds = Array(selectedPointIds).sorted()
        print("Total selected points: \(selectedPointIds.count)")
        print("Selected point IDs: \(sortedIds)")
        
        // Update status label
        statusLabel.text = "Selected: \(selectedPointIds.count)"
        
        // Clear any active sketch
        sketchEditor.stop()
        sketchEditor.clearGeometry()
        
        // Clear shape overlays
        shapesOverlay.graphics.removeAllObjects()
        
        // Clear button selection
        selectedButton?.configuration?.background.backgroundColor = .clear
        selectedButton = nil
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
        
        // Create buttons with SF Symbols
        let rectangleButton = createButton(systemName: "rectangle", title: "Rectangle")
        let lassoButton = createButton(systemName: "lasso", title: "Lasso")
        let ovalButton = createButton(systemName: "circle", title: "Ellipse")
        let lineButton = createButton(systemName: "line.diagonal", title: "Line")
        let undoButton = createButton(systemName: "arrow.uturn.backward", title: "Undo")
        
        // Add buttons to stack view
        bottomBar.addArrangedSubview(rectangleButton)
        bottomBar.addArrangedSubview(lassoButton)
        bottomBar.addArrangedSubview(ovalButton)
        bottomBar.addArrangedSubview(lineButton)
        bottomBar.addArrangedSubview(undoButton)
        
        // Update mapView constraints
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.bottomAnchor.constraint(equalTo: bottomBarBackground.topAnchor)
        ])
    }

    // Updated button creation method
    private func createButton(systemName: String, title: String) -> UIButton {
        let button = UIButton(type: .system)
        
        // Configure button
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: systemName)
        config.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(scale: .large)
        config.imagePadding = 8
        
        // Add background color for selected state
        config.background.backgroundColor = .clear
        config.background.cornerRadius = 8
        button.configuration = config
        
        // Set accessibility label
        button.accessibilityLabel = title
        
        // Add target
        button.addTarget(self, action: #selector(bottomBarButtonTapped(_:)), for: .touchUpInside)
        
        // Store the title in the button's tag for identification
        button.accessibilityIdentifier = title
        
        return button
    }

    @objc private func bottomBarButtonTapped(_ sender: UIButton) {
        guard let title = sender.accessibilityIdentifier else { return }
        print("\(title) button tapped")
        
        // Unhighlight previous button
        selectedButton?.configuration?.background.backgroundColor = .clear
        
        // Handle undo differently - don't highlight it
        if title == "Undo" {
            handleUndo()
            return
        }
        
        // Highlight current button
        sender.configuration?.background.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.3)
        selectedButton = sender
        
        let creationModes: KeyValuePairs = [
            "Arrow": AGSSketchCreationMode.arrow,
            "Ellipse": .ellipse,
            "Lasso": .freehandPolygon,
            "FreehandPolyline": .freehandPolyline,
            "Multipoint": .multipoint,
            "Point": .point,
            "Polygon": .polygon,
            "Line": .freehandPolyline,
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
            
            // CHANGE: Use Vancouver coordinates
            let centerPoint = AGSPoint(x: -123.1207, y: 49.2827, spatialReference: .wgs84())
            
            // Add the initial example point with id 0
            let initialGraphic = AGSGraphic(geometry: centerPoint, symbol: markerSymbol, attributes: ["id": 0, "name": "Center Point"])
            pointsOverlay.graphics.add(initialGraphic)
            
            // Generate 48 more random points around the initial point and add them to the overlay
            for i in 1..<49 { // Start from 1 since center point is 0
                let randomX = centerPoint.x + Double.random(in: -0.01...0.01)  // This creates points within ~1km radius
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
    
    deinit {
        if let observer = barItemObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

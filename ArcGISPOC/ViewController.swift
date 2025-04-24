//
//  ViewController.swift
//  ArcGISPOC
//
//  Created by XING ZHAO on 2025-04-02.
//

import UIKit
import ArcGIS

class ViewController: UIViewController, AGSGeoViewTouchDelegate {
    var pointsOverlay = AGSGraphicsOverlay() // For points
    var shapesOverlay = AGSGraphicsOverlay() // For shapes
    var sketchEditor = AGSSketchEditor()
    var barItemObserver: NSObjectProtocol!
    private var lastAddedGraphic: AGSGraphic?
    private var selectedButton: UIButton?
    private var selectedPointIds: Set<Int> = []
    private var selectedGeometries: [AGSGeometry] = []
    private var geometrySelectionsStack: [(geometry: AGSGeometry, selectedIds: Set<Int>)] = []
    private var currentCreationMode: AGSSketchCreationMode?
    private var cgiPointIds: Set<Int> = []
    private var panGestureRecognizer: UIPanGestureRecognizer?
    private var startPoint: AGSPoint?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemBackground
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance
        navigationController?.navigationBar.compactAppearance = appearance
        navigationController?.setNavigationBarHidden(false, animated: false)
        navigationItem.title = "Map Selection"  // Optional: add a title
        
        // Setup navigation bar buttons
        setupNavigationBar()
        
        view.addSubview(mapView)
        mapView.backgroundColor = .systemBackground
        
        // Set initial viewpoint with 0 rotation
        mapView.setViewpoint(AGSViewpoint(
            center: AGSPoint(x: -123.1207, y: 49.2827, spatialReference: .wgs84()),
            scale: 25000,
            rotation: 0  // Ensure map starts without rotation
        ))
        
        // Clear and reinitialize graphics overlays
        mapView.graphicsOverlays.removeAllObjects()
        
        // Initialize instance variables properly
        self.pointsOverlay.opacity = 1.0
        self.shapesOverlay.opacity = 1.0
        self.shapesOverlay.isVisible = true
        
        // Add overlays to map using instance variables
        mapView.graphicsOverlays.addObjects(from: [self.pointsOverlay, self.shapesOverlay])
        
        // Set the touch delegate
        mapView.touchDelegate = self
        
        // Load or add points
        if hasSavedPoints() {
            loadSavedPoints()
        } else {
            addCustomPoints()
        }
        //addCustomPoints()
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
        
        setupPanGesture()
        
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
            // Store current selection state before adding new one
            let previousSelectedIds = selectedPointIds
            
            if geometry is AGSPolyline {
                selectPointsNearPolyline(geometry as! AGSPolyline)
            } else {
                selectPointsInsideShape(with: geometry)
            }
            
            // Store the geometry and its newly selected points
            let newlySelectedIds = selectedPointIds.subtracting(previousSelectedIds)
            geometrySelectionsStack.append((geometry: geometry, selectedIds: newlySelectedIds))
            
            // Clear the sketch editor and shapes overlay after selection is complete
            DispatchQueue.main.async {
                self.sketchEditor.clearGeometry()
                self.shapesOverlay.graphics.removeAllObjects()
                
                // Reset sketch editor mode and button state
                self.sketchEditor.stop()
                self.currentCreationMode = nil
                self.selectedButton?.configuration?.background.backgroundColor = .clear
                self.selectedButton = nil
                
                // Update status label with selected count
                self.statusLabel.text = self.selectedPointIds.isEmpty ? "Unselected" : "Selected: \(self.selectedPointIds.count)"
            }
        }
    }

    private func selectPointsInsideShape(with geometry: AGSGeometry) {
        selectedGeometries.append(geometry)
        
        var pointsToToggle = Set<Int>()
        
        // First pass: identify points that will be toggled
        for graphic in pointsOverlay.graphics as! [AGSGraphic] {
            if let pointGeometry = graphic.geometry as? AGSPoint,
               let id = graphic.attributes["id"] as? Int {
                // Skip CGI points
                if cgiPointIds.contains(id) { continue }
                
                if pointGeometry.spatialReference != geometry.spatialReference {
                    guard let projectedPoint = AGSGeometryEngine.projectGeometry(pointGeometry, to: geometry.spatialReference!) else { continue }
                    
                    if AGSGeometryEngine.geometry(projectedPoint, within: geometry) {
                        pointsToToggle.insert(id)
                    }
                } else {
                    if AGSGeometryEngine.geometry(pointGeometry, within: geometry) {
                        pointsToToggle.insert(id)
                    }
                }
            }
        }
        
        // Second pass: toggle selections
        for graphic in pointsOverlay.graphics as! [AGSGraphic] {
            if let id = graphic.attributes["id"] as? Int,
               pointsToToggle.contains(id) {
                graphic.isSelected = !graphic.isSelected
                updatePointAppearance(graphic: graphic, isSelected: graphic.isSelected)
                
                if graphic.isSelected {
                    selectedPointIds.insert(id)
                } else {
                    selectedPointIds.remove(id)
                }
            }
        }
        
        // Store this operation in the undo stack
        geometrySelectionsStack.append((geometry: geometry, selectedIds: pointsToToggle))
        
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
        // CHANGE: Increase buffer distance from 1.5 to 5.0 for better point selection
        if let bufferedGeometry = AGSGeometryEngine.bufferGeometry(polyline, byDistance: 50.0) {
            selectedGeometries.append(bufferedGeometry)
            
            var pointsToToggle = Set<Int>()
            
            // First pass: identify points that will be toggled
            for graphic in pointsOverlay.graphics as! [AGSGraphic] {
                if let pointGeometry = graphic.geometry as? AGSPoint,
                   let id = graphic.attributes["id"] as? Int {
                    // Skip CGI points
                    if cgiPointIds.contains(id) { continue }
                    
                    if pointGeometry.spatialReference != bufferedGeometry.spatialReference {
                        guard let projectedPoint = AGSGeometryEngine.projectGeometry(pointGeometry, to: bufferedGeometry.spatialReference!) else { continue }
                        
                        if AGSGeometryEngine.geometry(projectedPoint, within: bufferedGeometry) {
                            pointsToToggle.insert(id)
                        }
                    } else {
                        if AGSGeometryEngine.geometry(pointGeometry, within: bufferedGeometry) {
                            pointsToToggle.insert(id)
                        }
                    }
                }
            }
            
            // Second pass: toggle selections
            for graphic in pointsOverlay.graphics as! [AGSGraphic] {
                if let id = graphic.attributes["id"] as? Int,
                   pointsToToggle.contains(id) {
                    graphic.isSelected = !graphic.isSelected
                    updatePointAppearance(graphic: graphic, isSelected: graphic.isSelected)
                    
                    if graphic.isSelected {
                        selectedPointIds.insert(id)
                    } else {
                        selectedPointIds.remove(id)
                    }
                }
            }
            
            // Store this operation in the undo stack
            geometrySelectionsStack.append((geometry: bufferedGeometry, selectedIds: pointsToToggle))
            
            // Sort and print selected IDs
            let sortedIds = Array(selectedPointIds).sorted()
            print("Total selected points: \(selectedPointIds.count)")
            print("Selected point IDs: \(sortedIds)")
            
            // Update status label
            DispatchQueue.main.async {
                self.statusLabel.text = "Selected: \(self.selectedPointIds.count)"
            }
        }
    }

    private func handleUndo() {
        guard !geometrySelectionsStack.isEmpty else { return }
        
        // Remove the last geometry and its selections
        let lastEntry = geometrySelectionsStack.removeLast()
        
        // Remove these points from the total selection
        selectedPointIds.subtract(lastEntry.selectedIds)
        
        // Update graphics selection state
        for graphic in pointsOverlay.graphics as! [AGSGraphic] {
            if let id = graphic.attributes["id"] as? Int {
                graphic.isSelected = selectedPointIds.contains(id)
                updatePointAppearance(graphic: graphic, isSelected: graphic.isSelected)
            }
        }
        
        // Clear any active sketch and reset mode
        sketchEditor.stop()
        sketchEditor.clearGeometry()
        currentCreationMode = nil
        shapesOverlay.graphics.removeAllObjects()
        
        // Clear button selection
        selectedButton?.configuration?.background.backgroundColor = .clear
        selectedButton = nil
        
        // Update status label with selected count
        statusLabel.text = selectedPointIds.isEmpty ? "Unselected" : "Selected: \(selectedPointIds.count)"
    }
    
    private func updatePointAppearance(graphic: AGSGraphic, isSelected: Bool) {
        if let oldSymbol = graphic.symbol as? AGSPictureMarkerSymbol,
           let image = oldSymbol.image {
            let color: UIColor = isSelected ? .systemBlue : .black
            let newSymbol = AGSPictureMarkerSymbol(image: image.withTintColor(color))
            newSymbol.width = oldSymbol.width
            newSymbol.height = oldSymbol.height
            graphic.symbol = newSymbol
        }
    }
    
    func geoView(_ geoView: AGSGeoView, didTapAtScreenPoint screenPoint: CGPoint, mapPoint: AGSPoint) {
        mapView.identify(pointsOverlay, screenPoint: screenPoint, tolerance: 12, returnPopupsOnly: false) { [weak self] result in
            guard let self,
                  !result.graphics.isEmpty,
                  let graphic = result.graphics.first,
                  let id = graphic.attributes["id"] as? Int else { return }
            
            let alertController = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
            let isSelected = graphic.isSelected
            let isCGI = self.cgiPointIds.contains(id)
            
            // Add "Select/Deselect" action
            let selectAction = UIAlertAction(title: isSelected ? "Deselect" : "Select", style: .default) { [weak self] _ in
                guard let self = self else { return }
                
                // Only allow selection if not CGI
                if !self.cgiPointIds.contains(id) {
                    graphic.isSelected = !graphic.isSelected
                    self.updatePointAppearance(graphic: graphic, isSelected: !isSelected)
                    
                    if graphic.isSelected {
                        self.selectedPointIds.insert(id)
                    } else {
                        self.selectedPointIds.remove(id)
                    }
                    
                    self.statusLabel.text = self.selectedPointIds.isEmpty ? "Unselected" : "Selected: \(self.selectedPointIds.count)"
                    
                    let sortedIds = Array(self.selectedPointIds).sorted()
                    print("Total selected points: \(self.selectedPointIds.count)")
                    print("Selected point IDs: \(sortedIds)")
                }
            }
            
            // Add "CGI/Cancel CGI" action
            let cgiAction = UIAlertAction(title: isCGI ? "Cancel CGI" : "CGI", style: .default) { [weak self] _ in
                guard let self = self else { return }
                
                if isCGI {
                    // Remove CGI status
                    self.cgiPointIds.remove(id)
                    
                    // Restore original appearance
                    if let oldSymbol = graphic.symbol as? AGSPictureMarkerSymbol,
                       let image = oldSymbol.image {
                        let newSymbol = AGSPictureMarkerSymbol(image: image.withTintColor(.black))
                        newSymbol.width = oldSymbol.width
                        newSymbol.height = oldSymbol.height
                        graphic.symbol = newSymbol
                    }
                    
                    print("Removed CGI status from point \(id)")
                } else {
                    // Add CGI status
                    self.cgiPointIds.insert(id)
                    
                    // If point was selected, deselect it
                    if graphic.isSelected {
                        graphic.isSelected = false
                        self.selectedPointIds.remove(id)
                        self.statusLabel.text = self.selectedPointIds.isEmpty ? "Unselected" : "Selected: \(self.selectedPointIds.count)"
                    }
                    
                    // Change point appearance for CGI
                    if let oldSymbol = graphic.symbol as? AGSPictureMarkerSymbol,
                       let image = oldSymbol.image {
                        let newSymbol = AGSPictureMarkerSymbol(image: image.withTintColor(.gray))
                        newSymbol.width = oldSymbol.width
                        newSymbol.height = oldSymbol.height
                        graphic.symbol = newSymbol
                    }
                    
                    print("Point \(id) marked as CGI")
                }
            }
            
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
            
            alertController.addAction(selectAction)
            alertController.addAction(cgiAction)
            alertController.addAction(cancelAction)
            
            DispatchQueue.main.async {
                self.present(alertController, animated: true)
            }
        }
    }

    private func setupNavigationBar() {
        let selectAllButton = UIBarButtonItem(image: UIImage(systemName: "checkmark.circle"),
                                            style: .plain,
                                            target: self,
                                            action: #selector(selectAllButtonTapped))
        
        let removeAllButton = UIBarButtonItem(image: UIImage(systemName: "xmark.circle"),
                                            style: .plain,
                                            target: self,
                                            action: #selector(removeAllButtonTapped))
        
        let demoButton = UIBarButtonItem(image: UIImage(systemName: "arrow.right.circle"),
                                       style: .plain,
                                       target: self,
                                       action: #selector(demoButtonTapped))
        
        navigationItem.rightBarButtonItems = [selectAllButton, removeAllButton, demoButton]
    }

    @objc private func removeAllButtonTapped() {
        selectedPointIds.removeAll()
        selectedGeometries.removeAll()
        geometrySelectionsStack.removeAll()
        
        // Deselect all non-CGI points
        for graphic in pointsOverlay.graphics as! [AGSGraphic] {
            if let id = graphic.attributes["id"] as? Int,
               !cgiPointIds.contains(id) {
                graphic.isSelected = false
                updatePointAppearance(graphic: graphic, isSelected: false)
            }
        }
        
        // Clear any active sketch and reset mode
        sketchEditor.stop()
        sketchEditor.clearGeometry()
        currentCreationMode = nil
        shapesOverlay.graphics.removeAllObjects()
        
        // Clear button selection
        selectedButton?.configuration?.background.backgroundColor = .clear
        selectedButton = nil
        
        statusLabel.text = "Unselected"
    }

    @objc private func selectAllButtonTapped() {
        selectedPointIds.removeAll()
        selectedGeometries.removeAll()
        geometrySelectionsStack.removeAll()
        
        // Select all points
        for graphic in pointsOverlay.graphics as! [AGSGraphic] {
            graphic.isSelected = true
            updatePointAppearance(graphic: graphic, isSelected: true)
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
    
    @objc private func demoButtonTapped() {
        let demoVC = DemoViewController()
        navigationController?.pushViewController(demoVC, animated: true)
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

    private func setupPanGesture() {
        panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGestureRecognizer?.isEnabled = false
        if let panGesture = panGestureRecognizer {
            mapView.addGestureRecognizer(panGesture)
        }
    }

    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: mapView)
        let mapPoint = mapView.screen(toLocation: location)
        print("handle pan gesture \(mapPoint)")
        
        switch gesture.state {
        case .began:
            startPoint = mapPoint
            self.shapesOverlay.graphics.removeAllObjects() // Clear previous shapes
            mapView.interactionOptions.isPanEnabled = false
            print("Pan began at: \(mapPoint.x), \(mapPoint.y)")
            
        case .changed:
            guard let start = startPoint else { return }
            print("Pan changed to: \(mapPoint.x), \(mapPoint.y)")
            
            let minX = min(start.x, mapPoint.x)
            let maxX = max(start.x, mapPoint.x)
            let minY = min(start.y, mapPoint.y)
            let maxY = max(start.y, mapPoint.y)
            
            // Create polygon for visualization
            let polygonBuilder = AGSPolygonBuilder(spatialReference: .wgs84())
            polygonBuilder.addPointWith(x: minX, y: minY)
            polygonBuilder.addPointWith(x: maxX, y: minY)
            polygonBuilder.addPointWith(x: maxX, y: maxY)
            polygonBuilder.addPointWith(x: minX, y: maxY)
            polygonBuilder.addPointWith(x: minX, y: minY)
            
            let geometry = polygonBuilder.toGeometry()
            
            // Clear previous shape and add new one
            self.shapesOverlay.graphics.removeAllObjects()
            
            // Create a highly visible fill symbol for rectangle
            let lineSymbol = AGSSimpleLineSymbol(style: .solid, color: .red, width: 4)
            let fillSymbol = AGSSimpleFillSymbol(
                style: .solid,
                color: UIColor.blue.withAlphaComponent(0.5),
                outline: lineSymbol
            )
            
            let graphic = AGSGraphic(geometry: geometry, symbol: fillSymbol)
            self.shapesOverlay.graphics.add(graphic)
            print("Added graphic to overlay. Graphics count: \(self.shapesOverlay.graphics.count)")
            
        case .ended:
            mapView.interactionOptions.isPanEnabled = true
            
            guard let start = startPoint else { return }
            let builder = AGSPolygonBuilder(spatialReference: .wgs84())
            let minX = min(start.x, mapPoint.x)
            let maxX = max(start.x, mapPoint.x)
            let minY = min(start.y, mapPoint.y)
            let maxY = max(start.y, mapPoint.y)
            
            builder.addPointWith(x: minX, y: minY)
            builder.addPointWith(x: maxX, y: minY)
            builder.addPointWith(x: maxX, y: maxY)
            builder.addPointWith(x: minX, y: maxY)
            builder.addPointWith(x: minX, y: minY)
            
            let geometry = builder.toGeometry()
            print("Pan ended with geometry: \(geometry)")
            selectPointsInsideShape(with: geometry)
            self.shapesOverlay.graphics.removeAllObjects()
            startPoint = nil
            print("Pan ended")
            
        default:
            break
        }
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
        
        // Enable/disable pan gesture based on rectangle mode
        panGestureRecognizer?.isEnabled = (title == "Rectangle")
        
        // Ensure map panning is enabled when switching away from rectangle mode
        if title != "Rectangle" {
            mapView.interactionOptions.isPanEnabled = true
        }
        
        // Highlight current button
        sender.configuration?.background.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.3)
        selectedButton = sender
        
        // Only set creation mode for non-rectangle tools
        if title != "Rectangle" {
            let creationModes: KeyValuePairs = [
                "Arrow": AGSSketchCreationMode.arrow,
                "Ellipse": .ellipse,
                "Lasso": .freehandPolygon,
                "FreehandPolyline": .freehandPolyline,
                "Multipoint": .multipoint,
                "Point": .point,
                "Polygon": .polygon,
                "Line": .freehandPolyline,
                "Triangle": .triangle
            ]
            
            for (name, mode) in creationModes {
                if name == title {
                    currentCreationMode = mode
                    sketchEditor.start(with: nil, creationMode: mode)
                    break
                }
            }
        }
    }

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
            for i in 1..<50 { // Start from 1 since center point is 0
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

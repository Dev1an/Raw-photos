//
//  PhotoEditingViewController.swift
//  Develop
//
//  Created by Damiaan on 24-11-16.
//  Copyright © 2016 Damiaan. All rights reserved.
//

import Cocoa
import Photos
import PhotosUI
import Witness

class PhotoEditingViewController: NSViewController, PHContentEditingController {

    var input: PHContentEditingInput?
	@IBOutlet weak var preview: NSImageView!
	var observer: Witness?
	
	var rawURL: URL?
	var xmpURL: URL?
	var jpgURL: URL?
	var xmpData: Data?

    // MARK: - PHContentEditingController

    func canHandle(_ adjustmentData: PHAdjustmentData) -> Bool {
        // Inspect the adjustmentData to determine whether your extension can work with past edits.
        // (Typically, you use its formatIdentifier and formatVersion properties to do this.)
        return true
    }
	
	@IBAction func openPhotoshop(_ sender: Any) {
		if let url = rawURL {
			NSWorkspace().open([url], withAppBundleIdentifier: "com.adobe.Photoshop", options: .default, additionalEventParamDescriptor: nil, launchIdentifiers: nil)
		}
	}
    
    func startContentEditing(with contentEditingInput: PHContentEditingInput, placeholderImage: NSImage) {
        // Present content for editing, and keep the contentEditingInput for use when closing the edit session.
        // If you returned true from canHandleAdjustmentData:, contentEditingInput has the original image and adjustment data.
        // If you returned false, the contentEditingInput has past edits "baked in".
        input = contentEditingInput
		if let previewURL = contentEditingInput.fullSizeImageURL {
			preview.image = NSImage(byReferencing: previewURL)
		}

		if let url = input?.fullSizeImageURL {
			let directory = NSTemporaryDirectory()
			rawURL = URL(fileURLWithPath: directory).appendingPathComponent("foto").appendingPathExtension(url.pathExtension)
			let fileWithoutExtension = rawURL!.deletingPathExtension()
			xmpURL = fileWithoutExtension.appendingPathExtension("xmp")
			jpgURL = fileWithoutExtension.appendingPathExtension("jpg")
			do {
				if FileManager.default.fileExists(atPath: rawURL!.path) {
					try FileManager.default.removeItem(at: rawURL!)
				}
				
				try FileManager.default.copyItem(at: url, to: rawURL!)
				if let adjustment = input!.adjustmentData, adjustment.formatIdentifier == "com.adobe.xmp" {
					try adjustment.data.write(to: xmpURL!)
				}
				openPhotoshop(self)
				observer = Witness(paths: [directory], flags: .FileEvents, changeHandler: filesUpdated)
			} catch { print(error) }
		}
    }
	
	static let createdOrModified = ([.ItemCreated, .ItemModified] as FileEventFlags).rawValue
	func filesUpdated(events: [FileEvent]) {
		if let xmpPath = xmpURL?.path, let jpgPath = jpgURL?.path {
			for event in events {
				if !event.flags.contains(.ItemRemoved) {
					if event.path.hasSuffix(xmpPath) && event.flags.rawValue & PhotoEditingViewController.createdOrModified != 0 {
						xmpData = try? Data(contentsOf: xmpURL!)
						return
					} else if event.path.hasSuffix(".jpg") && event.flags.contains(.ItemCreated) {
						print(event.flags)
						print("new", event.path)
						print("old", jpgPath)
						if (!event.path.hasSuffix(jpgPath)) {
							try? FileManager.default.removeItem(at: jpgURL!)
							jpgURL = URL(fileURLWithPath: event.path)
							print("deleted old path")
						}
						preview.image = NSImage(byReferencing: jpgURL!)
						print("")
					}
				}
			}
		}
	}
    
    func finishContentEditing(completionHandler: @escaping ((PHContentEditingOutput?) -> Void)) {
        // Update UI to reflect that editing has finished and output is being rendered.
        
        // Render and provide output on a background queue.
        DispatchQueue.global().async {
            // Create editing output from the editing input.
            let output = PHContentEditingOutput(contentEditingInput: self.input!)
			
            // Provide new adjustments and render output to given location.
			if let data = self.xmpData {
				output.adjustmentData = PHAdjustmentData(formatIdentifier: "com.adobe.xmp", formatVersion: "0.1", data: data)
			}
			
			if let renderdFile = self.jpgURL {
				do {
					try FileManager.default.moveItem(at: renderdFile, to: output.renderedContentURL)
				} catch {
					print(error)
				}
			}
			
            // Call completion handler to commit edit to Photos.
            completionHandler(output)
			
            // Clean up temporary files, etc.
			self.cleanUpTempFiles()
        }
    }

    var shouldShowCancelConfirmation: Bool {
        // Determines whether a confirmation to discard changes should be shown to the user on cancel.
        // (Typically, this should be "true" if there are any unsaved changes.)
        return false
    }

    func cancelContentEditing() {
        // Clean up temporary files, etc.
        // May be called after finishContentEditingWithCompletionHandler: while you prepare output.
		cleanUpTempFiles()
    }

	func cleanUpTempFiles() {
		print("cancel")
		if let rawFile = rawURL, let xmpFile = xmpURL, let jpgFile = jpgURL {
			try? FileManager.default.removeItem(at: rawFile)
			try? FileManager.default.removeItem(at: xmpFile)
			try? FileManager.default.removeItem(at: jpgFile)
			print("remove files")
		}
		
		observer = nil
	}
}

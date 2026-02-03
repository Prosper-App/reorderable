//
//  Bindings.swift
//  Reorderable
//
//  Created by Gabriel Royer on 2/4/25.
//

import SwiftUI

/// Safely retrieves a value from a dictionary, crashing with a descriptive message if the key is missing.
/// Used in Binding initializers where the dictionary is guaranteed to contain all keys from the same data source.
private func requireValue<K: Hashable, V>(_ map: [K: V], forKey key: K) -> V {
  guard let value = map[key] else {
    preconditionFailure("Reorderable: element ID not found in binding map. This indicates a data inconsistency.")
  }
  return value
}

public extension ReorderableVStack {

  /// Creates a reorderable vertical stack that computes its rows on demande from an underlying collection of identifable data and update the
  /// order of those datum based on the user's interaction.
  ///
  /// - Parameters:
  ///   - data: A collection of identifiable data for computing the vertical stack
  ///   - content: A view builder that creates the view for a single element of the list.
  init (
    _ data: Binding<Data>,
    @ViewBuilder content: @escaping (Binding<Data.Element>) -> Content
  ) where Data: RandomAccessCollection, Data: MutableCollection, Data.Element: Identifiable {
    let idToBindingMap = Dictionary(uniqueKeysWithValues: data.map({binding in
      (binding.wrappedValue.id, binding)
    }))

    self.init(
      data.wrappedValue,
      onMove: { from, to in
        withAnimation {
          data.wrappedValue.move(fromOffsets: IndexSet(integer: from),
                                 toOffset: (to > from) ? to + 1 : to)
        }
      },
      content: { element in
        content(requireValue(idToBindingMap, forKey: element.id))
      })
  }

  /// Creates a reorderable vertical stack that computes its rows on demande from an underlying collection of identifable data and update the
  /// order of those datum based on the user's interaction.
  ///
  /// - Parameters:
  ///   - data: A collection of identifiable data for computing the vertical stack
  ///   - content: A view builder that creates the view for a single element of the list, with an extra boolean parameter indicating whether the user is currently dragging the element.
  init (
    _ data: Binding<Data>,
    @ViewBuilder content: @escaping (Binding<Data.Element>, Bool) -> Content
  ) where Data: RandomAccessCollection, Data: MutableCollection, Data.Element: Identifiable {
    let idToBindingMap = Dictionary(uniqueKeysWithValues: data.map({binding in
      (binding.wrappedValue.id, binding)
    }))

    self.init(
      data.wrappedValue,
      onMove: { from, to in
        withAnimation {
          data.wrappedValue.move(fromOffsets: IndexSet(integer: from),
                                 toOffset: (to > from) ? to + 1 : to)
        }
      },
      content: { element, isDragging in
        content(requireValue(idToBindingMap, forKey: element.id), isDragging)
      })
  }
}

public extension ReorderableHStack {

  /// Creates a reorderable horizontal stack that computes its rows on demande from an underlying collection of identifable data and update the
  /// order of those datum based on the user's interaction.
  ///
  /// - Parameters:
  ///   - data: A collection of identifiable data for computing the horizontal stack
  ///   - content: A view builder that creates the view for a single element of the list.
  init (
    _ data: Binding<Data>,
    @ViewBuilder content: @escaping (Binding<Data.Element>) -> Content
  ) where Data: RandomAccessCollection, Data: MutableCollection, Data.Element: Identifiable {
    let idToBindingMap = Dictionary(uniqueKeysWithValues: data.map({binding in
      (binding.wrappedValue.id, binding)
    }))

    self.init(
      data.wrappedValue,
      onMove: { from, to in
        withAnimation {
          data.wrappedValue.move(fromOffsets: IndexSet(integer: from),
                                 toOffset: (to > from) ? to + 1 : to)
        }
      },
      content: { element in
        content(requireValue(idToBindingMap, forKey: element.id))
      })
  }

  /// Creates a reorderable horizontal stack that computes its rows on demande from an underlying collection of identifable data and update the
  /// order of those datum based on the user's interaction.
  ///
  /// - Parameters:
  ///   - data: A collection of identifiable data for computing the horizontal stack
  ///   - content: A view builder that creates the view for a single element of the list, with an extra boolean parameter indicating whether the user is currently dragging the element.
  init (
    _ data: Binding<Data>,
    @ViewBuilder content: @escaping (Binding<Data.Element>, Bool) -> Content
  ) where Data: RandomAccessCollection, Data: MutableCollection, Data.Element: Identifiable {
    let idToBindingMap = Dictionary(uniqueKeysWithValues: data.map({binding in
      (binding.wrappedValue.id, binding)
    }))

    self.init(
      data.wrappedValue,
      onMove: { from, to in
        withAnimation {
          data.wrappedValue.move(fromOffsets: IndexSet(integer: from),
                                 toOffset: (to > from) ? to + 1 : to)
        }
      },
      content: { element, isDragging in
        content(requireValue(idToBindingMap, forKey: element.id), isDragging)
      })
  }
}

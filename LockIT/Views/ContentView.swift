import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: FolderListViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("LockIT").font(.largeTitle).bold()
                Spacer()
                HStack(spacing: 8) {
                    Button(action: { viewModel.recoverLockedFile() }) {
                        Label("Select Encrypted File", systemImage: "doc.badge.plus")
                    }
                    .help("Select a .lockit file to decrypt and add to LockIT")
                    
                    Button(action: { viewModel.chooseFolder() }) {
                        Label("Choose Folder", systemImage: "folder")
                    }
                    
                    Button(action: { viewModel.createFolder() }) {
                        Label("Create Folder", systemImage: "plus")
                    }
                }
            }

            List {
                ForEach(viewModel.folders, id: \.id) { folder in
                    HStack {
                        Image(systemName: folder.isLocked ? "lock.fill" : "lock.open")
                            .foregroundColor(folder.isLocked ? .red : .green)
                        VStack(alignment: .leading) {
                            Text(folder.name).font(.headline)
                            Text(folder.originalPath).font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        if folder.isLocked {
                            Button("Unlock") { Task { await viewModel.unlock(folder) } }
                        } else {
                            Button("Lock") { Task { await viewModel.lock(folder) } }
                        }
                        Button(role: .destructive) { viewModel.removeFolder(folder) } label: { Image(systemName: "trash") }
                    }
                }
            }
            .frame(minHeight: 300)

            if let error = viewModel.errorMessage {
                Text(error).foregroundColor(.red)
            }
        }
        .padding(20)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView().environmentObject(FolderListViewModel.shared)
            .frame(width: 700, height: 420)
    }
}


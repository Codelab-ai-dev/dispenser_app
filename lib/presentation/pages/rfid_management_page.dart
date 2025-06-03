import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/models/rfid_tag.dart';
import '../../domain/usecases/get_all_tags_usecase.dart';
import '../../domain/usecases/save_tag_usecase.dart';
import '../../domain/usecases/update_tag_usecase.dart';
import '../../domain/usecases/delete_tag_usecase.dart';

class RfidManagementPage extends StatefulWidget {
  const RfidManagementPage({Key? key}) : super(key: key);

  @override
  State<RfidManagementPage> createState() => _RfidManagementPageState();
}

class _RfidManagementPageState extends State<RfidManagementPage> {
  final GetAllTagsUseCase _getAllTagsUseCase = GetAllTagsUseCase();
  final SaveTagUseCase _saveTagUseCase = SaveTagUseCase();
  final UpdateTagUseCase _updateTagUseCase = UpdateTagUseCase();
  final DeleteTagUseCase _deleteTagUseCase = DeleteTagUseCase();

  List<RfidTag> _tags = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final tags = await _getAllTagsUseCase.execute();
      setState(() {
        _tags = tags;
        _isLoading = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar tags: $e'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteTag(String id) async {
    try {
      await _deleteTagUseCase.execute(id);
      await _loadTags();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tag eliminado correctamente'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar tag: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _toggleTagStatus(RfidTag tag) async {
    try {
      final updatedTag = tag.copyWith(isActive: !tag.isActive);
      await _updateTagUseCase.execute(updatedTag);
      await _loadTags();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al actualizar tag: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showAddEditTagDialog({RfidTag? tag}) {
    final isEditing = tag != null;
    final hexCodeController = TextEditingController(text: isEditing ? tag.hexCode : '');
    final descriptionController = TextEditingController(text: isEditing ? tag.description : '');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Editar Tag RFID' : 'Añadir Nuevo Tag RFID'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: hexCodeController,
                  decoration: const InputDecoration(
                    labelText: 'Código Hexadecimal',
                    hintText: 'Ej: A1B2C3D4',
                    prefixIcon: Icon(Icons.tag),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                  ],
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor ingrese el código hexadecimal';
                    }
                    if (value.length < 4) {
                      return 'El código debe tener al menos 4 caracteres';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción',
                    hintText: 'Ej: Tarjeta de Acceso Principal',
                    prefixIcon: Icon(Icons.description),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor ingrese una descripción';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                try {
                  if (isEditing) {
                    // Actualizar tag existente
                    final updatedTag = tag.copyWith(
                      hexCode: hexCodeController.text.trim(),
                      description: descriptionController.text.trim(),
                    );
                    await _updateTagUseCase.execute(updatedTag);
                  } else {
                    // Crear nuevo tag
                    final newTag = RfidTag(
                      id: '',
                      hexCode: hexCodeController.text.trim(),
                      description: descriptionController.text.trim(),
                    );
                    await _saveTagUseCase.execute(newTag);
                  }
                  
                  Navigator.of(context).pop();
                  await _loadTags();
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isEditing 
                          ? 'Tag actualizado correctamente' 
                          : 'Tag añadido correctamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: Text(isEditing ? 'Actualizar' : 'Añadir'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de Tags RFID'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTags,
            tooltip: 'Recargar',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _tags.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.nfc,
                        size: 64,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No hay tags RFID registrados',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => _showAddEditTagDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Añadir Nuevo Tag'),
                      ),
                    ],
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tags RFID Registrados',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Los tags activos serán autorizados para despacho',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _tags.length,
                          itemBuilder: (context, index) {
                            final tag = _tags[index];
                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: tag.isActive ? Colors.green : Colors.red,
                                  child: Icon(
                                    Icons.nfc,
                                    color: Colors.white,
                                  ),
                                ),
                                title: Text(
                                  tag.hexCode,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                subtitle: Text(tag.description),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Switch(
                                      value: tag.isActive,
                                      onChanged: (value) => _toggleTagStatus(tag),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.blue),
                                      onPressed: () => _showAddEditTagDialog(tag: tag),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text('Confirmar eliminación'),
                                            content: Text(
                                                '¿Está seguro que desea eliminar el tag ${tag.hexCode}?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.of(context).pop(),
                                                child: const Text('Cancelar'),
                                              ),
                                              ElevatedButton(
                                                onPressed: () {
                                                  Navigator.of(context).pop();
                                                  _deleteTag(tag.id);
                                                },
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: Colors.red,
                                                  foregroundColor: Colors.white,
                                                ),
                                                child: const Text('Eliminar'),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEditTagDialog(),
        child: const Icon(Icons.add),
        tooltip: 'Añadir nuevo tag RFID',
      ),
    );
  }
}

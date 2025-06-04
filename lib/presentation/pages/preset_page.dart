import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class PresetPage extends StatefulWidget {
  const PresetPage({Key? key}) : super(key: key);

  @override
  State<PresetPage> createState() => _PresetPageState();
}

class _PresetPageState extends State<PresetPage> {
  final TextEditingController _presetController = TextEditingController();
  double _presetValue = 0.0;
  bool _isValid = false;

  @override
  void initState() {
    super.initState();
    _presetController.addListener(_validateInput);
  }

  @override
  void dispose() {
    _presetController.dispose();
    super.dispose();
  }

  void _validateInput() {
    final input = _presetController.text;
    if (input.isEmpty) {
      setState(() {
        _isValid = false;
        _presetValue = 0.0;
      });
      return;
    }

    try {
      final value = double.parse(input);
      setState(() {
        _isValid = value > 0.0 && value <= 1000.0; // Límite máximo de 1000 litros
        _presetValue = value;
      });
    } catch (e) {
      setState(() {
        _isValid = false;
      });
    }
  }

  void _confirmPreset() {
    if (_isValid) {
      // Devolver el valor del preset a la página anterior
      context.pop<double>(_presetValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurar Preset'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Ingresa la cantidad de litros a despachar:',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _presetController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: InputDecoration(
                labelText: 'Litros',
                hintText: 'Ej: 20.5',
                suffixText: 'L',
                border: const OutlineInputBorder(),
                errorText: _presetController.text.isNotEmpty && !_isValid
                    ? 'Ingresa un valor válido entre 0.01 y 1000 litros'
                    : null,
              ),
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(height: 32),
            Text(
              'Preset seleccionado: ${_presetValue.toStringAsFixed(2)} L',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _isValid ? Colors.blue : Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'Presets rápidos:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: [5.0, 10.0, 20.0, 50.0, 100.0].map((preset) {
                return ElevatedButton(
                  onPressed: () {
                    _presetController.text = preset.toString();
                    _validateInput();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade100,
                    foregroundColor: Colors.blue.shade800,
                  ),
                  child: Text('${preset.toStringAsFixed(1)} L'),
                );
              }).toList(),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: _isValid ? _confirmPreset : null,
              icon: const Icon(Icons.check_circle),
              label: const Text('Confirmar y Continuar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => context.pop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }
}

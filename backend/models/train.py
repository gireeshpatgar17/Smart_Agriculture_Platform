# import os
# import numpy as np
# import tensorflow as tf

# from tensorflow.keras import layers, Model
# from sklearn.model_selection import train_test_split
# from sklearn.metrics import classification_report


# # ============================================================
# # CONFIGURATION
# # ============================================================

# DATASET_DIR = r"D:\YOUR_PATH\dataset"

# IMG_SIZE = 224
# BATCH_SIZE = 32
# EPOCHS = 30

# DISEASES = [
#     "brown_spot",
#     "healthy",
#     "leaf_blast",
#     "sheath_blight"
# ]

# DISEASE_TO_ID = {
#     "brown_spot": 0,
#     "healthy": 1,
#     "leaf_blast": 2,
#     "sheath_blight": 3
# }

# NUM_DISEASES = 4
# NUM_SEVERITIES = 10       # LV0 - LV9


# # ============================================================
# # LOAD DATASET
# # ============================================================

# image_paths = []
# disease_labels = []
# severity_labels = []


# valid_extensions = (
#     ".jpg",
#     ".jpeg",
#     ".png",
#     ".bmp",
#     ".webp"
# )


# for disease in DISEASES:

#     disease_path = os.path.join(DATASET_DIR, disease)

#     if not os.path.exists(disease_path):
#         print("Missing:", disease_path)
#         continue

#     disease_id = DISEASE_TO_ID[disease]

#     # --------------------------------------------------------
#     # HEALTHY
#     # --------------------------------------------------------

#     if disease == "healthy":

#         for root, dirs, files in os.walk(disease_path):

#             for file in files:

#                 if file.lower().endswith(valid_extensions):

#                     image_paths.append(
#                         os.path.join(root, file)
#                     )

#                     disease_labels.append(disease_id)

#                     # Healthy = LV0
#                     severity_labels.append(0)

#     # --------------------------------------------------------
#     # DISEASES WITH LV FOLDERS
#     # --------------------------------------------------------

#     else:

#         for severity_folder in os.listdir(disease_path):

#             severity_path = os.path.join(
#                 disease_path,
#                 severity_folder
#             )

#             if not os.path.isdir(severity_path):
#                 continue

#             # Example: LV1 -> 1
#             if not severity_folder.upper().startswith("LV"):
#                 continue

#             try:
#                 severity_id = int(
#                     severity_folder.upper().replace("LV", "")
#                 )

#             except ValueError:
#                 continue

#             if severity_id < 1 or severity_id > 9:
#                 continue

#             for root, dirs, files in os.walk(severity_path):

#                 for file in files:

#                     if file.lower().endswith(valid_extensions):

#                         image_paths.append(
#                             os.path.join(root, file)
#                         )

#                         disease_labels.append(disease_id)

#                         severity_labels.append(severity_id)


# # ============================================================
# # CONVERT TO NUMPY
# # ============================================================

# image_paths = np.array(image_paths)

# disease_labels = np.array(
#     disease_labels,
#     dtype=np.int32
# )

# severity_labels = np.array(
#     severity_labels,
#     dtype=np.int32
# )


# print("\nTotal images:", len(image_paths))

# print("\nDisease distribution:")

# for disease, disease_id in DISEASE_TO_ID.items():

#     count = np.sum(disease_labels == disease_id)

#     print(
#         disease,
#         ":",
#         count
#     )


# print("\nSeverity distribution:")

# for severity in range(NUM_SEVERITIES):

#     count = np.sum(
#         severity_labels == severity
#     )

#     print(
#         f"LV{severity}:",
#         count
#     )


# # ============================================================
# # TRAIN / VALIDATION / TEST SPLIT
# # ============================================================

# indices = np.arange(len(image_paths))


# # First: 80% train, 20% temporary
# train_indices, temp_indices = train_test_split(
#     indices,
#     test_size=0.20,
#     random_state=42,
#     stratify=disease_labels
# )


# # Second: temporary -> validation + test
# val_indices, test_indices = train_test_split(
#     temp_indices,
#     test_size=0.50,
#     random_state=42,
#     stratify=disease_labels[temp_indices]
# )


# print("\nDataset split:")
# print("Train:", len(train_indices))
# print("Validation:", len(val_indices))
# print("Test:", len(test_indices))


# # ============================================================
# # IMAGE LOADING
# # ============================================================

# def load_image(path, disease, severity):

#     image = tf.io.read_file(path)

#     image = tf.image.decode_image(
#         image,
#         channels=3,
#         expand_animations=False
#     )

#     image.set_shape(
#         [None, None, 3]
#     )

#     image = tf.image.resize(
#         image,
#         [IMG_SIZE, IMG_SIZE]
#     )

#     image = tf.cast(
#         image,
#         tf.float32
#     ) / 255.0

#     return image, {
#         "disease_output": disease,
#         "severity_output": severity
#     }


# # ============================================================
# # DATA AUGMENTATION
# # ============================================================

# augmentation = tf.keras.Sequential([

#     layers.RandomFlip(
#         "horizontal"
#     ),

#     layers.RandomRotation(
#         0.10
#     ),

#     layers.RandomZoom(
#         0.10
#     ),

#     layers.RandomContrast(
#         0.10
#     )

# ])


# # ============================================================
# # CREATE TF DATASET
# # ============================================================

# def create_dataset(indices, training=False):

#     paths = image_paths[indices]

#     diseases = disease_labels[indices]

#     severities = severity_labels[indices]


#     dataset = tf.data.Dataset.from_tensor_slices(
#         (
#             paths,
#             diseases,
#             severities
#         )
#     )


#     def process(path, disease, severity):

#         image, labels = load_image(
#             path,
#             disease,
#             severity
#         )

#         if training:

#             image = augmentation(
#                 image,
#                 training=True
#             )

#         return image, labels


#     dataset = dataset.map(
#         process,
#         num_parallel_calls=tf.data.AUTOTUNE
#     )


#     if training:

#         dataset = dataset.shuffle(
#             1000
#         )


#     dataset = dataset.batch(
#         BATCH_SIZE
#     )

#     dataset = dataset.prefetch(
#         tf.data.AUTOTUNE
#     )

#     return dataset


# train_dataset = create_dataset(
#     train_indices,
#     training=True
# )

# val_dataset = create_dataset(
#     val_indices
# )

# test_dataset = create_dataset(
#     test_indices
# )


# # ============================================================
# # CNN MODEL
# # ============================================================

# inputs = layers.Input(
#     shape=(IMG_SIZE, IMG_SIZE, 3),
#     name="leaf_image"
# )


# # ------------------------------------------------------------
# # CNN BACKBONE
# # ------------------------------------------------------------

# x = layers.Conv2D(
#     32,
#     (3, 3),
#     padding="same",
#     activation="relu"
# )(inputs)

# x = layers.BatchNormalization()(x)

# x = layers.MaxPooling2D()(x)


# x = layers.Conv2D(
#     64,
#     (3, 3),
#     padding="same",
#     activation="relu"
# )(x)

# x = layers.BatchNormalization()(x)

# x = layers.MaxPooling2D()(x)


# x = layers.Conv2D(
#     128,
#     (3, 3),
#     padding="same",
#     activation="relu"
# )(x)

# x = layers.BatchNormalization()(x)

# x = layers.MaxPooling2D()(x)


# x = layers.Conv2D(
#     256,
#     (3, 3),
#     padding="same",
#     activation="relu"
# )(x)

# x = layers.BatchNormalization()(x)

# x = layers.MaxPooling2D()(x)


# # ------------------------------------------------------------
# # SHARED FEATURE REPRESENTATION
# # ------------------------------------------------------------

# x = layers.GlobalAveragePooling2D()(x)

# x = layers.Dense(
#     256,
#     activation="relu"
# )(x)

# x = layers.Dropout(
#     0.4
# )(x)


# # ============================================================
# # DISEASE HEAD
# # ============================================================

# disease_branch = layers.Dense(
#     128,
#     activation="relu"
# )(x)

# disease_branch = layers.Dropout(
#     0.3
# )(disease_branch)

# disease_output = layers.Dense(
#     NUM_DISEASES,
#     activation="softmax",
#     name="disease_output"
# )(disease_branch)


# # ============================================================
# # SEVERITY HEAD
# # ============================================================

# severity_branch = layers.Dense(
#     128,
#     activation="relu"
# )(x)

# severity_branch = layers.Dropout(
#     0.3
# )(severity_branch)

# severity_output = layers.Dense(
#     NUM_SEVERITIES,
#     activation="softmax",
#     name="severity_output"
# )(severity_branch)


# # ============================================================
# # FINAL MODEL
# # ============================================================

# model = Model(
#     inputs=inputs,
#     outputs=[
#         disease_output,
#         severity_output
#     ]
# )


# # ============================================================
# # COMPILE
# # ============================================================

# model.compile(

#     optimizer=tf.keras.optimizers.Adam(
#         learning_rate=0.0001
#     ),

#     loss={
#         "disease_output":
#             "sparse_categorical_crossentropy",

#         "severity_output":
#             "sparse_categorical_crossentropy"
#     },

#     metrics={
#         "disease_output":
#             ["accuracy"],

#         "severity_output":
#             ["accuracy"]
#     }
# )


# model.summary()


# # ============================================================
# # CALLBACKS
# # ============================================================

# callbacks = [

#     tf.keras.callbacks.EarlyStopping(
#         monitor="val_loss",
#         patience=7,
#         restore_best_weights=True
#     ),

#     tf.keras.callbacks.ReduceLROnPlateau(
#         monitor="val_loss",
#         factor=0.5,
#         patience=3,
#         min_lr=1e-7
#     ),

#     tf.keras.callbacks.ModelCheckpoint(
#         "rice_disease_cnn.keras",
#         monitor="val_loss",
#         save_best_only=True
#     )
# ]


# # ============================================================
# # TRAIN
# # ============================================================

# history = model.fit(

#     train_dataset,

#     validation_data=val_dataset,

#     epochs=EPOCHS,

#     callbacks=callbacks
# )


# # ============================================================
# # EVALUATE
# # ============================================================

# print("\nEvaluating model...")

# results = model.evaluate(
#     test_dataset,
#     return_dict=True
# )

# print("\nTest results:")

# for key, value in results.items():

#     print(
#         f"{key}: {value:.4f}"
#     )


# # ============================================================
# # SAVE FINAL MODEL
# # ============================================================

# model.save(
#     "rice_disease_final.keras"
# )

# print(
#     "\nModel saved as rice_disease_final.keras"
# )
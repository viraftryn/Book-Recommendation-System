{
 "cells": [
  {
   "cell_type": "code",
   "execution_count": 1,
   "id": "e2fde5b2-d0c3-4792-8640-5c340440e2c1",
   "metadata": {},
   "outputs": [],
   "source": [
    "from flask import Flask, jsonify, request\n",
    "from flask_cors import CORS\n",
    "import numpy as np\n",
    "import pickle\n",
    "import json\n",
    "import os"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 2,
   "id": "b5af46e4-962d-4e99-b8f4-0ed025e395ff",
   "metadata": {},
   "outputs": [
    {
     "data": {
      "text/plain": [
       "<flask_cors.extension.CORS at 0x107d865b0>"
      ]
     },
     "execution_count": 2,
     "metadata": {},
     "output_type": "execute_result"
    }
   ],
   "source": [
    "app = Flask(__name__)\n",
    "CORS(app) # allows ios app to make requests"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 3,
   "id": "7f192470-5358-4e35-8f33-8bfd0504e1d3",
   "metadata": {},
   "outputs": [],
   "source": [
    "# Load trained model \n",
    "with open('svd_model.pkl', 'rb') as f:\n",
    "    svd_model = pickle.load(f)\n",
    "\n",
    "with open('trainset.pkl', 'rb') as f:\n",
    "    trainset = pickle.load(f)\n",
    "\n",
    "with open('books_metadata.json', 'r') as f:\n",
    "    books_list = json.load(f)\n",
    "    books_meta = {b['isbn']: b for b in books_list}"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 4,
   "id": "5ca0002b-9afd-4619-a693-54a337c21ad2",
   "metadata": {},
   "outputs": [],
   "source": [
    "# Extract SVD components for fast numpy prediction\n",
    "global_mean = svd_model.trainset.global_mean\n",
    "user_factors = svd_model.pu # (n_users, n_factors)\n",
    "item_factors = svd_model.qi # (n_items, n_factors)\n",
    "user_biases = svd_model.bu # (n_users, )\n",
    "item_biases = svd_model.bi # (n_items, )"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 5,
   "id": "20190b27-a6af-40ea-9b15-c940af37d48f",
   "metadata": {},
   "outputs": [],
   "source": [
    "# Computing popular books for cold-start fallback\n",
    "item_scores = {}\n",
    "for iid in range(trainset.n_items):\n",
    "    ratings = [r for (_, r) in trainset.ir[iid]]\n",
    "    if len(ratings) >= 5:\n",
    "        isbn = trainset.to_raw_iid(iid)\n",
    "        item_scores[isbn] = float(np.mean(ratings))\n",
    "\n",
    "popular_books = sorted(item_scores.items(), \n",
    "                       key=lambda x: x[1], \n",
    "                       reverse=True)[:50]"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 6,
   "id": "34a07a50-ae7d-4643-832f-e38aff0fe31e",
   "metadata": {},
   "outputs": [],
   "source": [
    "def predict_rating(user_inner, item_inner):\n",
    "    \"\"\"Raw SVD prediction using numpy\"\"\"\n",
    "    pred = (global_mean\n",
    "            + user_biases[user_inner]\n",
    "            + item_biases[item_inner]\n",
    "            + np.dot(user_factors[user_inner], \n",
    "                     item_factors[item_inner]))\n",
    "    return float(np.clip(pred, 5.0, 10.0))"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 7,
   "id": "aa0ded73-cfab-4ebf-95f5-ebaef2e3dc59",
   "metadata": {},
   "outputs": [],
   "source": [
    "def get_recommendations(user_id, n=10):\n",
    "    \"\"\"\n",
    "    Get top-N recommendations for a user.\n",
    "    Returns None if user is unknown (cold start).\n",
    "    \"\"\"\n",
    "    try:\n",
    "        uid = trainset.to_inner_uid(str(user_id))\n",
    "    except ValueError:\n",
    "        return None  # user not in training data\n",
    "\n",
    "    # Books this user already rated — exclude from recs\n",
    "    rated_items = {iid for (iid, _) in trainset.ur[uid]}\n",
    "\n",
    "    # Score all unrated items\n",
    "    scores = []\n",
    "    for iid in range(trainset.n_items):\n",
    "        if iid in rated_items:\n",
    "            continue\n",
    "        score = predict_rating(uid, iid)\n",
    "        isbn  = trainset.to_raw_iid(iid)\n",
    "        scores.append((isbn, score))\n",
    "\n",
    "    # Sort by score descending, take top N\n",
    "    scores.sort(key=lambda x: x[1], reverse=True)\n",
    "    return scores[:n]"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 8,
   "id": "d9ed8440-e211-4ad2-bf39-6a5f77356a3f",
   "metadata": {},
   "outputs": [],
   "source": [
    "def enrich_with_metadata(isbn_score_list):\n",
    "    \"\"\"Add book title/author to ISBN+score results.\"\"\"\n",
    "    enriched = []\n",
    "    for isbn, score in isbn_score_list:\n",
    "        meta = books_meta.get(isbn, {})\n",
    "        enriched.append({\n",
    "            'isbn':   isbn,\n",
    "            'title':  meta.get('title',  'Unknown Title'),\n",
    "            'author': meta.get('author', 'Unknown Author'),\n",
    "            'year':   meta.get('year',   ''),\n",
    "            'score':  round(score, 3),\n",
    "            'image_s': meta.get('image_s', ''), \n",
    "            'image_m': meta.get('image_m', ''),\n",
    "            'image_l': meta.get('image_l', '')\n",
    "        })\n",
    "    return enriched"
   ]
  },
  {
   "cell_type": "markdown",
   "id": "635b9618-4fc0-4228-9f7c-acb16e399c34",
   "metadata": {},
   "source": [
    "**API Endpoints**"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": 9,
   "id": "bc3ff2ce-d7c7-4883-b22e-8711631d8963",
   "metadata": {},
   "outputs": [],
   "source": [
    "@app.route('/health', methods=['GET'])\n",
    "def health():\n",
    "    \"\"\"Check is server is running\"\"\"\n",
    "    return jsontify({\n",
    "        'status': 'ok',\n",
    "        'users': trainset.n_users,\n",
    "        'items': trainset.n_items\n",
    "    }), 200\n",
    "\n",
    "@app.route('/recommend/<user_id>', methods=['GET'])\n",
    "def recommend(user_id):\n",
    "    n = request.args.get('n', default=10, type=int)\n",
    "    n = min(n, 50) # cap at 50\n",
    "\n",
    "    recs = get_recommendations(user_id, n=n)\n",
    "\n",
    "    if recs is None:\n",
    "        # Cold Start\n",
    "        return jsonify({\n",
    "            'user_id': user_id,\n",
    "            'status': 'success',\n",
    "            'recommendations': enrich_with_metadata(recs)\n",
    "        }), 200\n",
    "\n",
    "@app.route('/predict', methods=['POST'])\n",
    "def predict():\n",
    "    # Predict rating for a specific user & book pair\n",
    "\n",
    "    data = request.get_json()\n",
    "    user_id = str(data.get('user_id', ''))\n",
    "    isbn = str(data.get('isbn', ''))\n",
    "\n",
    "    if not user_id or not isbn:\n",
    "        return jsonify({'error': 'user_id and isbn required'}), 400\n",
    "\n",
    "    pred = svd_model.predict(user_id, isbn)\n",
    "    return jsonify({\n",
    "        'user_id': user_id,\n",
    "        'isbn': isbn,\n",
    "        'predicted_rating': round(pred.est, 3)\n",
    "    }), 200\n",
    "\n",
    "@app.route('/popular', methods=['GET'])\n",
    "def popular():\n",
    "    # Get popular books for new users\n",
    "\n",
    "    n = request.args.get('n', default=10, type=int)\n",
    "    return jsonify({\n",
    "        'status': 'success',\n",
    "        'recommendations': enrich_with_metadata(popular_books[:n])\n",
    "    }), 200\n",
    "\n",
    "@app.route('/users', methods=['GET'])\n",
    "def list_users():\n",
    "    # Check is a user exists in the model\n",
    "    \n",
    "    user_id = request.args.get('user_id', '')\n",
    "\n",
    "    try:\n",
    "        trainset.to_inner_uid(str(user_id))\n",
    "        exists = True\n",
    "    except ValueError:\n",
    "        exists = False\n",
    "\n",
    "    return jsonify({\n",
    "        'user_id': user_id,\n",
    "        'exists': exists\n",
    "    }), 200"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "id": "ad05f7f5-66ee-402b-ae54-7dc40037eefd",
   "metadata": {},
   "outputs": [],
   "source": [
    "if __name__ == '__main__':\n",
    "    port = int(os.environ.get('PORT', 5000))\n",
    "    app.run(host='0.0.0.0', port=port, debug=False)"
   ]
  },
  {
   "cell_type": "code",
   "execution_count": null,
   "id": "a52ab068-e9ba-4202-9704-de8d84291c03",
   "metadata": {},
   "outputs": [],
   "source": []
  }
 ],
 "metadata": {
  "kernelspec": {
   "display_name": "Python 3 (ipykernel)",
   "language": "python",
   "name": "python3"
  },
  "language_info": {
   "codemirror_mode": {
    "name": "ipython",
    "version": 3
   },
   "file_extension": ".py",
   "mimetype": "text/x-python",
   "name": "python",
   "nbconvert_exporter": "python",
   "pygments_lexer": "ipython3",
   "version": "3.9.25"
  }
 },
 "nbformat": 4,
 "nbformat_minor": 5
}

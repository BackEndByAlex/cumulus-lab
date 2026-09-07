resource "openstack_blockstorage_volume_v3" "campus_web_server_volume" {
  name = "campus-web-server-volume"

  size        = 5
  volume_type = "SSD"

  availability_zone = "nova"
}

resource "openstack_compute_volume_attach_v2" "campus_web_server_volume_attach" {
  instance_id = openstack_compute_instance_v2.campus_web_server.id
  volume_id   = openstack_blockstorage_volume_v3.campus_web_server_volume.id
}

using System;

namespace MRSDistCompWebApp.Models
{
    public class ModelSchema
    {
        public Guid Id { get; set; }
        public string Name { get; set; }       
        public string Description { get; set; }
        public string Version { get; set; }
        public string SchemaJSON { get; set; }
        public string SchemaBin { get; set; }       
    }
}
